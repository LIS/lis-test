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
import sys
import time
import logging

from utils import constants
from utils.cmdshell import SSHClient
from report.db_utils import upload_results
from paramiko.ssh_exception import NoValidConnectionsError

from providers.amazon_service import AWSConnector
from providers.azure_service import AzureConnector
from providers.gcp_service import GCPConnector

logging.basicConfig(format='%(asctime)s %(levelname)s: %(message)s',
                    datefmt='%y/%m/%d %H:%M:%S', level=logging.INFO)
log = logging.getLogger(__name__)


class SetupTestEnv:
    """
    Setup test environment.
    """
    def __init__(self, provider=None, vm_count=None, test_type=None, disk_size=None, raid=None,
                 keyid=None, secret=None, token=None, subscriptionid=None, tenantid=None,
                 projectid=None, imageid=None, instancetype=None, user=None, localpath=None,
                 region=None, zone=None, sriov=False, kernel=None):
        """
        Init AWS connector to create and configure AWS ec2 instances.
        :param provider Service provider to be used e.g. azure, aws, gce.
        :param vm_count: Number of VMs to prepare
        :param test_type: vm_disk > 1 VM with disk (Orion and Sysbench)
                          no_disk > No disk attached (Redis, Memcached, Apache_bench)
                          db_disk > Second VM with disk (MariaDB, MongoDB)
                          cluster_disk > All VMs have disks (Terasort)
        :param disk_size:
        :param raid: Bool or Int (the number of disks), to specify if a RAID will be configured
        :param keyid: user key for executing remote connection
        :param secret: user secret for executing remote connection
        :param token: GCE refresh token obtained with gcloud sdk
        :param subscriptionid: Azure specific subscription id
        :param tenantid: Azure specific tenant id
        :param projectid: GCE specific project id
        :param imageid: AWS OS AMI image id or
                        Azure image references offer and sku: e.g. 'UbuntuServer#16.04.0-LTS' or
                        GCE image family, e.g. 'ubuntu-1604-lts'
        :param instancetype: AWS instance resource type e.g 'd2.4xlarge' or
                            Azure hardware profile vm size e.g. 'Standard_DS14_v2' or
                            GCE instance size e.g. 'n1-highmem-16'
        :param user: remote ssh user for the instance
        :param localpath: localpath where the logs should be downloaded, and the
                            default path for other necessary tools
        :param region: region to connect to
        :param zone: zone where other resources should be available
        :param sriov: bool for configuring SR-IOV or not
        :param kernel: kernel deb name to install provided in localpath
        :rtype Tuple
        :return: connector <Connector>,
                 vm_ips <VM private IPs dict>,
                 device <attached disk devices>,
                 ssh_client <ssh clients dict>
        """
        self.provider = provider
        self.vm_count = vm_count
        self.test_type = test_type
        self.disk_size = disk_size
        self.raid = raid
        self.keyid = keyid
        self.secret = secret
        self.token = token
        self.subscriptionid = subscriptionid
        self.tenantid = tenantid
        self.projectid = projectid
        self.imageid = imageid
        self.instancetype = instancetype
        self.user = user
        self.localpath = localpath
        self.region = region
        self.zone = zone
        self.sriov = sriov
        self.kernel = kernel

        # create and generate setup details
        try:
            self.connector = self.create_connector()
            self.vms = self.create_instances()
            self.device = self.get_disk_devices()
            self.ssh_client, self.vm_ips = self.get_instance_details()
            self.perf_tuning()
            self.reconnect_sshclient()
        except Exception as e:
            log.exception(e)
            if self.connector:
                self.connector.teardown()
            raise

    def create_connector(self):
        """
        Create connector by provider.
        :return: connector
        """
        connector = None
        if self.provider == constants.AWS:
            connector = AWSConnector(keyid=self.keyid, secret=self.secret, imageid=self.imageid,
                                     instancetype=self.instancetype, user=self.user,
                                     localpath=self.localpath, region=self.region, zone=self.zone)
        elif self.provider == constants.AZURE:
            connector = AzureConnector(clientid=self.keyid, secret=self.secret,
                                       subscriptionid=self.subscriptionid, tenantid=self.tenantid,
                                       imageid=self.imageid, instancetype=self.instancetype,
                                       user=self.user, localpath=self.localpath,
                                       location=self.region, sriov=self.sriov)
        elif self.provider == constants.GCE:
            connector = GCPConnector(clientid=self.keyid, secret=self.secret, token=self.token,
                                     projectid=self.projectid, imageid=self.imageid,
                                     instancetype=self.instancetype, user=self.user,
                                     localpath=self.localpath, zone=self.zone)
        if connector:
            connector.connect()
            return connector
        else:
            raise Exception('Unsupported provider or connector failed.')

    def create_instances(self):
        """
        Create instances.
        :return: VM instances
        """
        open(self.connector.host_key_file, 'w').close()
        vms = {}
        for i in xrange(1, self.vm_count + 1):
            vms[i] = self.connector.create_vm()
        return vms

    def reconnect_sshclient(self):
        if self.provider == constants.AWS:
            log.info('The provider is AWS, reconnect sshclient')
            for i in xrange(1, self.vm_count + 1):
                self.ssh_client[i].connect()

    def get_instance_details(self):
        """
        Create ssh client and get vm IPs
        :return: ssh_client, vm_ips
        """
        ssh_client = {}
        vm_ips = {}
        for i in xrange(1, self.vm_count + 1):
            if self.provider == constants.AWS:
                ssh_client[i] = self.connector.wait_for_ping(self.vms[i])
                # SRIOV is enabled by default on AWS for the tested platforms
                # if sriov == constants.ENABLED:
                #     ssh_client[i] = connector.enable_sr_iov(vms[i], ssh_client[i])
                self.vms[i].update()
                vm_ips[i] = self.vms[i].private_ip_address
            elif self.provider == constants.AZURE:
                ssh_client[i] = SSHClient(server=self.vms[i].name + self.connector.dns_suffix,
                                          host_key_file=self.connector.host_key_file,
                                          user=self.connector.user,
                                          ssh_key_file=os.path.join(
                                                  self.connector.localpath,
                                                  self.connector.key_name + '.pem'))
                ip = ssh_client[i].run(
                        'ifconfig eth0 | grep "inet" | cut -d: -f2 | awk -F " " \'{print $2}\' | head -n 1')
                log.info('vm ip {}'.format(ip))
                vm_ips[i] = ip[1].strip()
            elif self.provider == constants.GCE:
                ssh_client[i] = self.connector.wait_for_ping(self.vms[i])
                vm_ips[i] = self.vms[i]['networkInterfaces'][0]['networkIP']
        return ssh_client, vm_ips

    def attach_raid_disks(self, vm_tag, disk_args):
        device = []
        for i in xrange(self.raid):
            if self.provider == constants.AWS:
                disk_args['device'] = '/dev/sd{}'.format(chr(120 - i))
                device.append(disk_args['device'].replace('sd', 'xvd'))
            elif self.provider == constants.AZURE:
                disk_args['device'] = i
                device.append('/dev/sd{}'.format(chr(99 + i)))
            elif self.provider == constants.GCE:
                device.append('/dev/sd{}'.format(chr(98 + i)))
            self.connector.attach_disk(self.vms[vm_tag], disk_size=self.disk_size, **disk_args)
        return device

    def get_disk_devices(self):
        if not self.test_type:
            return None
        device = None
        disk_args = {}
        if self.provider == constants.AWS:
            device = constants.DEVICE_AWS.replace('sd', 'xvd')
            disk_args['iops'] = 5000
            disk_args['volume_type'] = self.connector.volume_type['ssd_io1']
            disk_args['device'] = constants.DEVICE_AWS
        elif self.provider == constants.AZURE:
            device = constants.DEVICE_AZURE
        elif self.provider == constants.GCE:
            # Note: using disk device order prediction,GCE API is not consistent in the disk naming
            # device = constants.DEVICE_GCE + disk_name
            device = constants.TEMP_DEVICE_GCE

        if self.test_type == constants.CLUSTER_DISK:
            self.connector.attach_disk(self.vms[1], disk_size=self.disk_size + 200, **disk_args)
            for i in xrange(2, self.vm_count + 1):
                self.connector.attach_disk(self.vms[i], disk_size=self.disk_size, **disk_args)
                time.sleep(3)
            return device

        vm_tag = None
        if self.test_type == constants.VM_DISK:
            vm_tag = 1
        elif self.test_type == constants.DB_DISK:
            vm_tag = 2

        if self.raid and type(self.raid) is int:
            return self.attach_raid_disks(vm_tag, disk_args)
        else:
            self.connector.attach_disk(self.vms[vm_tag], disk_size=self.disk_size, **disk_args)

        return device

    def perf_tuning(self):
        current_path = os.path.dirname(sys.modules['__main__'].__file__)
        for i in range(1, self.vm_count + 1):
            log.info('Running perf tuning on {}'.format(self.vm_ips[i]))
            self.ssh_client[i].connect()
            self.ssh_client[i].put_file(os.path.join(current_path, 'tests', 'perf_tuning.sh'),
                                        '/tmp/perf_tuning.sh')
            self.ssh_client[i].run('chmod +x /tmp/perf_tuning.sh')
            self.ssh_client[i].run("sed -i 's/\r//' /tmp/perf_tuning.sh")
            params = [self.provider]
            if '.deb' in self.kernel:
                log.info('Uploading kernel {} on {}'.format(self.kernel, self.vm_ips[i]))
                self.ssh_client[i].put_file(os.path.join(self.localpath, self.kernel),
                                            '/tmp/{}'.format(self.kernel))
                params.append('/tmp/{}'.format(self.kernel))
            self.ssh_client[i].run('/tmp/perf_tuning.sh {}'.format(' '.join(params)))
            if self.provider in [constants.AWS, constants.GCE]:
                self.ssh_client[i] = self.connector.restart_vm(self.vms[i])
            elif self.provider == constants.AZURE:
                self.vms[i] = self.connector.restart_vm(self.vms[i].name)
                # TODO add custom kernel support for all providers - only azure support
                self.ssh_client[i] = SSHClient(server=self.vms[i].name + self.connector.dns_suffix,
                                               host_key_file=self.connector.host_key_file,
                                               user=self.connector.user,
                                               ssh_key_file=os.path.join(
                                                       self.connector.localpath,
                                                       self.connector.key_name + '.pem'))
                ip = self.ssh_client[i].run(
                        'ifconfig eth0 | grep "inet" | cut -d: -f2 | awk -F " " \'{print $2}\' | head -n 1')
                self.vm_ips[i] = ip[1].strip()

    def run_test(self, ssh_vm_conf=0, testname=None, test_cmd=None, results_path=None, raid=False,
                 ssh_raid=1, timeout=constants.TIMEOUT):
        try:
            if all(client is not None for client in self.ssh_client.values()):
                current_path = os.path.dirname(sys.modules['__main__'].__file__)
                # enable key auth between instances
                for i in xrange(1, ssh_vm_conf + 1):
                    self.ssh_client[i].put_file(os.path.join(self.localpath,
                                                             self.connector.key_name + '.pem'),
                                                '/home/{}/.ssh/id_rsa'.format(self.user))
                    self.ssh_client[i].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(self.user))
                if raid:
                    self.ssh_client[ssh_raid].put_file(os.path.join(
                            current_path, 'tests', 'raid.sh'), '/tmp/raid.sh')
                    self.ssh_client[ssh_raid].run('chmod +x /tmp/raid.sh')
                    self.ssh_client[ssh_raid].run("sed -i 's/\r//' /tmp/raid.sh")
                    self.ssh_client[ssh_raid].run('/tmp/raid.sh 0 {} {}'.format(raid, ' '.join(
                            self.device)))
                bash_testname = 'run_{}.sh'.format(testname)
                self.ssh_client[1].put_file(os.path.join(current_path, 'tests', bash_testname),
                                            '/tmp/{}'.format(bash_testname))
                self.ssh_client[1].run('chmod +x /tmp/{}'.format(bash_testname))
                self.ssh_client[1].run("sed -i 's/\r//' /tmp/{}".format(bash_testname))
                log.info('Starting background command {}'.format(test_cmd))
                channel = self.ssh_client[1].run_pty(test_cmd)
                _, pid, _ = self.ssh_client[1].run(
                        "ps aux | grep -v grep | grep {} | awk '{{print $2}}'".format(
                                bash_testname))
                self._wait_for_pid(self.ssh_client[1], bash_testname, pid, timeout=timeout)
                channel.close()
                self.ssh_client[1].get_file('/tmp/{}.zip'.format(testname), results_path)
        except Exception as e:
            log.exception(e)
            raise
        finally:
            if self.connector:
                self.connector.teardown()

    @staticmethod
    def _wait_for_pid(ssh_client, bash_testname, pid, timeout=constants.TIMEOUT):
        t = 0
        while t < timeout:
            try:
                _, new_pid, _ = ssh_client.run(
                        "ps aux | grep -v grep | grep {} | awk '{{print $2}}'".format(
                                bash_testname))
                if new_pid != pid:
                    return
            except NoValidConnectionsError:
                log.debug('NoValidConnectionsError, will retry in 60 seconds')
                time.sleep(60)
                t += 60
            time.sleep(60)
            t += 60
        else:
            raise Exception('Timeout waiting for process to end.'.format(timeout))

    def run_test_nohup(self, ssh_vm_conf=0, test_cmd=None, timeout=constants.TIMEOUT, track=None):
        try:
            if all(client is not None for client in self.ssh_client.values()):
                current_path = os.path.dirname(sys.modules['__main__'].__file__)
                # enable key auth between instances
                for i in xrange(1, ssh_vm_conf + 1):
                    self.ssh_client[i].put_file(os.path.join(self.localpath,
                                                             self.connector.key_name + '.pem'),
                                                '/home/{}/.ssh/id_rsa'.format(self.user))
                    self.ssh_client[i].run('chmod 0600 /home/{0}/.ssh/id_rsa'.format(self.user))
                log.info('Starting run nohup command {}'.format(test_cmd))
                self.ssh_client[1].run(test_cmd)
                self._wait_for_command(self.ssh_client[1], track, timeout=timeout)
        except Exception as e:
            log.exception(e)
            raise
        finally:
            log.info('Finish to run nohup command {}'.format(test_cmd))

    @staticmethod
    def _wait_for_command(ssh_client, track, timeout=constants.TIMEOUT):
        t = 0
        while t < timeout:
            try:
                _, p_count, _  = ssh_client.run(
                        "ps aux | grep -v grep | grep {} | awk '{{print $2}}' | wc -l".format(
                                track))
                if int(p_count) == 0 :
                    return
            except NoValidConnectionsError:
                log.debug('NoValidConnectionsError, will retry in 60 seconds')
                time.sleep(60)
                t += 60
            time.sleep(60)
            t += 60
        else:
            raise Exception('Timeout waiting for process to end.'.format(timeout))