"""
Linux on Hyper-V and Azure Test Code, ver. 1.0.0
Copyright (c) Microsoft Corporation

All rights reserved
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

See the Apache Version 2.0 License for specific language governing
permissions and limitations under the License.
"""

import os
import time
import logging
import ConfigParser
import uuid
import random
import string

from utils import constants
from azure.common.credentials import ServicePrincipalCredentials
from azure.mgmt.resource import ResourceManagementClient
from azure.mgmt.storage import StorageManagementClient
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.compute import ComputeManagementClient

from msrestazure.azure_exceptions import CloudError

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class AzureConnector:
    """
    Azure connector that uses azure-sdk-for-python plugin.
    """
    def __init__(self, clientid=None, secret=None, subscriptionid=None, tenantid=None,
                 imageid=None, instancetype=None, user=None, localpath=None, location=None,
                 sriov=None):
        """
        Init Azure connector to create and configure instance VMs.
        :param clientid: client id obtained from Azure AD application (create key)
            https://docs.microsoft.com/en-us/azure/azure-resource-manager/
            resource-group-create-service-principal-portal
        :param secret: client secret obtained from the Azure AD application
        :param subscriptionid: Azure subscription id
        :param tenantid: Azure tenant/directory id
        :param imageid: Azure requires multiple image references (publisher, offer, sku, version),
            for simplicity only the offer and sku should be provided: e.g. UbuntuServer#16.04.0-LTS
        :param instancetype: Azure hardware profile or vm size e.g. 'Standard_DS1'
        :param user: remote ssh user for the VM
        :param localpath: localpath where the logs should be downloaded, and the
                            default path for other necessary tools
        :param location: Azure global location to connect to
        :param sriov: Enable/disable Accelerated Networking option
        """
        credentials = ServicePrincipalCredentials(client_id=clientid, secret=secret,
                                                  tenant=tenantid)

        self.resource_client = ResourceManagementClient(credentials, subscriptionid)
        self.compute_client = ComputeManagementClient(credentials, subscriptionid)
        self.storage_client = StorageManagementClient(credentials, subscriptionid)
        self.network_client = NetworkManagementClient(credentials, subscriptionid)

        self.instancetype = instancetype
        self.localpath = localpath
        self.sriov = sriov
        self.host_key_file = os.path.join(self.localpath, 'known_hosts')
        if not location:
            self.location = 'westus'
        else:
            self.location = location

        if 'Ubuntu' in imageid:
            self.imageid = {'publisher': 'Canonical',
                            'offer': imageid.split('#')[0],
                            'sku': imageid.split('#')[1],
                            'version': 'latest'
                            }

        self.user = user
        self.dns_suffix = '.{}.cloudapp.azure.com'.format(self.location)
        tag = str(uuid.uuid4()).replace('-', '')
        self.key_name = 'test_ssh_key'
        self.group_name = 'middleware_' + tag
        self.vmnet_name = 'm_vmnet' + tag
        self.subnet_name = 'm_subnet' + tag
        self.os_disk_name = 'm_osdisk' + tag
        self.storage_account = 'stor' + tag[:18]
        self.ip_config_name = 'm_ipconfig' + tag
        self.nic_name = 'm_nic' + tag

        self.subnet = None
        self.vms = []

    def connect(self):
        """
        Obtain the Azure connector by authenticating. This also creates the keypair and
        security group for the instance.
        """
        log.info('Creating/updating resource group: {} with location: {}'.format(self.group_name,
                                                                                 self.location))
        self.resource_client.resource_groups.create_or_update(self.group_name,
                                                              {'location': self.location})
        if self.instancetype == 'Standard_NC6' or self.instancetype == 'Standard_D16_v3' or self.instancetype == 'Standard_D64_v3' or self.instancetype == 'Standard_E16_v3':
            sku = 'standard_lrs'
        else:
            sku = 'premium_lrs'
        storage_op = self.storage_client.storage_accounts.create(self.group_name,
                                                                 self.storage_account,
                                                                 {'sku': {'name': sku},
                                                                  'kind': 'storage',
                                                                  'location': self.location})
        storage_op.wait()

        create_vmnet = self.network_client.virtual_networks.create_or_update(
                self.group_name, self.vmnet_name,
                {'location': self.location,
                 'address_space': {'address_prefixes': ['10.10.0.0/16']}})
        create_vmnet.wait()

        create_subnet = self.network_client.subnets.create_or_update(
                self.group_name, self.vmnet_name, self.subnet_name,
                {'address_prefix': '10.10.10.0/24'})
        self.subnet = create_subnet.result()

    def create_vm(self, config_file=None, dns_suffix=None):
        """
        Create an Azure VM instance.
        :return: VirtualMachine object
        or
        :return: user, pass, VirtualMachine object in case of windows machine
        """
        config = None
        if config_file:
            log.info('Assuming Windows Vm creation')
            log.info('Looking up Windows VM credentials in {}\*.windows.'.format(config_file))
            vm_file = [os.path.join(config_file, c) for c in os.listdir(config_file)
                       if c.endswith('.windows')][0]
            # read credentials from file - should be present in the localpath provided to runner
            config = ConfigParser.ConfigParser()
            config.read(vm_file)
            if 'Image' not in config.sections():
                imageid = {'publisher': 'MicrosoftWindowsServer',
                           'offer': 'WindowsServer',
                           'sku': '2016-Datacenter',
                           'version': 'latest'}
            else:
                private_image = self.compute_client.images.get(
                        config.get('Image', 'resource_group'), config.get('Image', 'name'))
                imageid = {'id': private_image.id}
            vm_name = ''.join(random.choice(string.ascii_lowercase) for _ in range(10))
            nic = self.create_nic(vm_name, nsg=True)
            vm_parameters = {
                'location': self.location,
                'os_profile': {
                    'computer_name': vm_name,
                    'admin_username': config.get('Windows', 'user'),
                    'admin_password': config.get('Windows', 'password'),
                    'windows_configuration': {'provision_vm_agent': True,
                                              'enable_automatic_updates': False}
                },
                'hardware_profile': {'vm_size': self.instancetype},
                'storage_profile': {
                    'image_reference': imageid,
                    'os_disk': {
                        'os_type': 'Windows',
                        'name': self.os_disk_name,
                        'caching': 'ReadWrite',
                        'create_option': 'fromImage'}},
                'network_profile': {'network_interfaces': [{'id': nic.id}]}
            }
        else:
            vm_name = self.imageid['offer'].lower() + str(time.time()).replace('.', '')
            nic = self.create_nic(vm_name)
            with open(os.path.join(self.localpath, self.key_name + '.pub'), 'r') as f:
                key_data = f.read()
            vm_parameters = {
                'location': self.location,
                'os_profile': {
                    'computer_name': vm_name,
                    'admin_username': self.user,
                    'linux_configuration': {
                        'disable_password_authentication': True,
                        'ssh': {
                            'public_keys': [{
                                'path': '/home/{}/.ssh/authorized_keys'.format(self.user),
                                'key_data': key_data}]}}},
                'hardware_profile': {'vm_size': self.instancetype},
                'storage_profile': {
                    'image_reference': self.imageid,
                    'os_disk': {
                        'name': self.os_disk_name,
                        'caching': 'None',
                        'create_option': 'fromImage',
                        'vhd': {'uri': 'https://{}.blob.core.windows.net/vhds/{}.vhd'.format(
                                self.storage_account, self.vmnet_name + str(time.time()))}}},
                'network_profile': {'network_interfaces': [{'id': nic.id}]}
            }
        vm_creation = self.compute_client.virtual_machines.create_or_update(
                self.group_name, vm_name, vm_parameters)
        vm_creation.wait()
        vm_instance = self.compute_client.virtual_machines.get(self.group_name, vm_name)
        log.info('Created VM: {}'.format(vm_name))
        vm_start = self.compute_client.virtual_machines.start(self.group_name, vm_name)
        vm_start.wait()
        log.info('Started VM: {}'.format(vm_name))
        self.vms.append(vm_instance)

        if config_file:
            ext = self.compute_client.virtual_machine_extensions.create_or_update(
                    self.group_name, vm_name, 'custom_extension_script',
                    {'location': self.location,
                     'publisher': 'Microsoft.Compute',
                     'virtual_machine_extension_type': 'CustomScriptExtension',
                     'type_handler_version': '1.7',
                     'auto_upgrade_minor_version': True,
                     'settings': {
                         'fileUris': ['https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-vm-winrm-windows/ConfigureWinRM.ps1',
                                      'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-vm-winrm-windows/makecert.exe',
                                      'https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/201-vm-winrm-windows/winrmconf.cmd'],
                         'commandToExecute': 'powershell -ExecutionPolicy Unrestricted -file ConfigureWinRM.ps1 {vm}'.format(vm='*'+dns_suffix)}
                     })
            log.info('Ran custom script on VM: {}'.format(ext.result()))
            return config.get('Windows', 'user'), config.get('Windows', 'password'), vm_instance
        else:
            return vm_instance

    def create_nic(self, vm_name, nsg=None):
        """
        Create an VM Network interface.
        :param vm_name VM name
        :param nsg <dict> containing security rules {}
        :return: NetworkInterface ClientRawResponse
        """
        create_public_ip = self.network_client.public_ip_addresses.create_or_update(
                self.group_name, vm_name + '-ip',
                {'location': self.location,
                 'public_ip_allocation_method': 'Dynamic',
                 'public_ip_address_version': 'IPv4',
                 'dns_settings': {
                     'domain_name_label': vm_name}})
        public_ip = create_public_ip.result()

        nic_parameters = {'location': self.location,
                          'ip_configurations': [{'name': self.ip_config_name,
                                                 'subnet': {'id': self.subnet.id},
                                                 'public_ip_address': {'id': public_ip.id}}]
                          }
        if self.sriov == constants.ENABLED:
            log.info('Adding Accelerated Networking')
            nic_parameters['enable_accelerated_networking'] = True
        if nsg:
            create_nsg = self.network_client.network_security_groups.create_or_update(
                    self.group_name, vm_name + '-nsg',
                    {'location': self.location})
            self.network_client.security_rules.create_or_update(
                    self.group_name, create_nsg.result().name, 'default-allow-rdp',
                    {'protocol': 'Tcp',
                     'source_address_prefix': '*',
                     'destination_address_prefix': '*',
                     'access': 'Allow',
                     'direction': 'Inbound',
                     'source_port_range': '*',
                     'destination_port_range': '3389',
                     'priority': 1000})
            self.network_client.security_rules.create_or_update(
                    self.group_name, create_nsg.result().name, 'wsman-https',
                    {'protocol': 'Tcp',
                     'source_address_prefix': '*',
                     'destination_address_prefix': '*',
                     'access': 'Allow',
                     'direction': 'Inbound',
                     'source_port_range': '*',
                     'destination_port_range': '5986',
                     'priority': 1001})
            log.info('Adding custom security group to NIC')
            nic_parameters['network_security_group'] = create_nsg.result()
        nic_name = self.nic_name + str(time.time())
        nic_op = self.network_client.network_interfaces.create_or_update(
                self.group_name, nic_name, nic_parameters)
        log.info('Created NIC: {}'.format(nic_name))
        return nic_op.result()

    def attach_disk(self, vm_instance, disk_size=0, device=0):
        """
        Creates and attached a disk to VM.
        :param vm_instance: VirtualMachine obj to attach the disk to
        :param disk_size: disk size in GB
        :param device: disk lun device
        :return disk_name: given disk name
        """
        disk_name = vm_instance.name + '_disk_' + str(time.time())
        disk_profile = {'name': disk_name,
                        'disk_size_gb': disk_size,
                        'caching': 'None',
                        'lun': device,
                        'vhd': {'uri': "http://{}.blob.core.windows.net/vhds/{}.vhd".format(
                                self.storage_account, disk_name)},
                        'create_option': 'Empty'}

        vm_instance.storage_profile.data_disks.append(disk_profile)
        vm_update = self.compute_client.virtual_machines.create_or_update(self.group_name,
                                                                          vm_instance.name,
                                                                          vm_instance)
        vm_update.wait()
        try:
            vm_update.result()
            log.info('Created disk: {}'.format(disk_name))
        except Exception as de:
            log.info(de)
        return disk_name

    def restart_vm(self, vm_name):
        """
        Restart instances VM.
        """
        vm_instance = self.compute_client.virtual_machines.get(self.group_name, vm_name)

        log.info('Restarting VM: {}'.format(vm_name))
        vm_restart = self.compute_client.virtual_machines.restart(self.group_name, vm_name)
        vm_restart.wait()
        time.sleep(120)

        return vm_instance

    def teardown(self):
        """
        Cleanup created instances and devices.
        """
        log.info("Running teardown.")
        # Delete Resource group and everything in it
        delete_resource_group = self.resource_client.resource_groups.delete(self.group_name)
        try:
            delete_resource_group.wait()
        except CloudError as ce:
            log.info(ce)
            if 'AuthorizationFailed' in ce:
                log.info("Resource group {} already removed".format(self.group_name))
        log.info("Deleted: {}".format(self.group_name))
