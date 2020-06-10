# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. 
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE 
# OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# This source code is just an example and it does not represent any software or product or service from my employer Microsoft. It is not an official Microsoft artifact and it is not endorsed in any way by Microsoft. 
# You should exercise your own judgement and prudence before using it. There is no one who is actively maintaining or supporting this project.
# 
# please customize to your needs
# no availability sets/zones used here, please add if needed for your purposes
# recommended to use a jumpbox or Azure bastion to access the SAP landscape
# use Azure keyvault for credentials
# include backup

AzSub=
AzLoc=
Workload=cust-s4     #change to your needs
RgName=rg-eun-${Workload}
VmAdminUsr=bob
VmImage=SUSE:SLES-SAP:12-SP4:latest
VnetName=vnet-eun-${Workload}
AppSubnetName=${VnetName}_sapapp
DbSubnetName=${VnetName}_sapdb
AppSubnetAddressPrefix=10.42.0.0/25     #change to your needs
DbSubnetAddressPrefix=10.42.0.128/26    #change to your needs
VnetAddressPrefix=10.42.0.0/24          #change to your needs
AppVmSize=Standard_D4s_v3               #change to your needs
DbVmSize=Standard_M32ls

az account set --subscription $AzSub
az group create -g $RgName -l $AzLoc

# create NSGs for subnets --- NSG rules created are just standard, please customize according your security requirements
# az network nsg create --resource-group $RgName --name nsg-$AppSubnetName
# az network nsg create --resource-group $RgName --name nsg-$DbSubnetName

az network vnet create --name $VnetName --address-prefixes $VnetAddressPrefix --subnet-name $AppSubnetName --subnet-prefixes $AppSubnetAddressPrefix --location $AzLoc --resource-group $RgName   
az network vnet subnet create --name $DbSubnetName --resource-group $RgName --vnet-name $VnetName --address-prefixes $DbSubnetAddressPrefix

# update NSG -associate with subnets
# az network vnet subnet update --resource-group $RgName --name $AppSubnetName --vnet-name $VnetName --network-security-group nsg-$AppSubnetName
# az network vnet subnet update --resource-group $RgName --name $DbSubnetName --vnet-name $VnetName --network-security-group nsg-$DbSubnetName
# az network nsg list --resource-group $RgName --output table

# please create your rules within the NSG according https://docs.microsoft.com/en-us/cli/azure/network/nsg/rule?view=azure-cli-latest#az-network-nsg-rule-create

#create PPG
az ppg create --resource-group $RgName --name ppg-euw-${Workload} --location $AzLoc --type Standard 

# DB server
VmName=vm-eun-${Workload}-db
NicName=${VmName}_nic1
az network public-ip create --name ${VmName}-pip --resource-group $RgName --dns-name ${VmName}-${RANDOM} --allocation-method dynamic # remove if not using public IP (only for sandbox/test)
az network nic create --name $NicName --resource-group $RgName --vnet-name $VnetName --subnet $DbSubnetName --accelerated-networking true --public-ip-address ${VmName}-pip
az vm create --name $VmName --resource-group $RgName  --os-disk-name ${VmName}-osdisk --os-disk-size-gb 64 --storage-sku Premium_LRS --size $DbVmSize  --location $AzLoc  --image $VmImage --admin-username=$VmAdminUsr --nics $NicName --ppg ppg-eun-${Workload}
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk0 --sku Premium_LRS --size 128 --lun 0 --new --caching None #/usr/sap
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk1 --sku Premium_LRS --size 512 --lun 1 --new --caching None #/hana/data disk1
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk2 --sku Premium_LRS --size 512 --lun 2 --new --caching None #/hana/data disk2
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk3 --sku Premium_LRS --size 512 --lun 3 --new --caching None #/hana/data disk3
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk4 --sku Premium_LRS --size 512 --lun 4 --new --caching None --enable-write-accelerator #/hana/log disk1
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk5 --sku Premium_LRS --size 512 --lun 5 --new --caching None --enable-write-accelerator #/hana/log disk2
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk6 --sku Premium_LRS --size 512 --lun 6 --new --caching ReadOnly  #/hana/shared

# enable Enable Azure Extension for SAP
az extension add --name aem
az vm aem set -g $RgName -n $VmName

PubIpFqdn=`az network public-ip list --resource-group $RgName| grep fqdn | grep $VmName | awk '{print $2}'| sed 's/.\{2\}$//'| cut -c2-`
# do stuff inside VM
ssh -oStrictHostKeyChecking=no ${VmAdminUsr}@${PubIpFqdn} << EOF
sudo pvcreate /dev/disk/azure/scsi1/lun0
sudo pvcreate /dev/disk/azure/scsi1/lun1
sudo pvcreate /dev/disk/azure/scsi1/lun2
sudo pvcreate /dev/disk/azure/scsi1/lun3
sudo pvcreate /dev/disk/azure/scsi1/lun4
sudo pvcreate /dev/disk/azure/scsi1/lun5
sudo pvcreate /dev/disk/azure/scsi1/lun6
sudo vgcreate vg_usr_sap /dev/disk/azure/scsi1/lun0
sudo lvcreate -n lv_usr_sap -l 100%FREE vg_usr_sap
sudo vgcreate vg_HANA_data /dev/disk/azure/scsi1/lun[123]
sudo lvcreate -n lv_HANA_data -l +100%FREE --stripesize 256 --stripes 3 vg_HANA_data
sudo vgcreate vg_HANA_log /dev/disk/azure/scsi1/lun[45]
sudo lvcreate -n lv_HANA_log -l +100%FREE --stripesize 32 --stripes 2 vg_HANA_log
sudo vgcreate vg_HANA_shared /dev/disk/azure/scsi1/lun6
sudo lvcreate -n lv_HANA_shared -l 100%FREE vg_HANA_shared
sudo mkfs.xfs /dev/mapper/vg_usr_sap-lv_usr_sap
sudo mkfs.xfs /dev/mapper/vg_HANA_log-lv_HANA_log
sudo mkfs.xfs /dev/mapper/vg_HANA_data-lv_HANA_data
sudo mkfs.xfs /dev/mapper/vg_HANA_shared-lv_HANA_shared
sudo mkdir -p /hana/data /hana/log /hana/shared /usr/sap
sudo su -
echo '/dev/mapper/vg_usr_sap-lv_usr_sap /usr/sap xfs defaults,nofail,nobarrier      0 2' >> /etc/fstab
echo '/dev/mapper/vg_HANA_log-lv_HANA_log /hana/log   xfs      defaults,nofail,nobarrier      0 2' >> /etc/fstab
echo '/dev/mapper/vg_HANA_data-lv_HANA_data /hana/data   xfs      defaults,nofail,nobarrier      0 2' >> /etc/fstab
echo '/dev/mapper/vg_HANA_shared-lv_HANA_shared /hana/shared   xfs      defaults,nofail,nobarrier      0 2' >> /etc/fstab
mount -a
sed -i 's/ResourceDisk.Format=n/ResourceDisk.Format=y/g' /etc/waagent.conf
sed -i 's/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g' /etc/waagent.conf
sed -i 's/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=20480/g' /etc/waagent.conf
systemctl restart waagent
swapon -s
zypper install -y saptune sapconf unrar #packet saptune,sapconf, dependencies for SAPHANA, SAP compatibility library, parameters for SAP"
zypper install -t pattern -y sap-hana
saptune solution apply HANA
saptune daemon start
reboot
EOF

# app server
VmName=vm-eun-${Workload}-app
NicName=${VmName}_nic1
az network public-ip create --name ${VmName}-pip --resource-group $RgName --dns-name ${VmName}-${RANDOM} --allocation-method dynamic # remove if not using public IP (only for sandbox/test), better to use jumpbox to access the SAP systems
az network nic create --name $NicName --resource-group $RgName --vnet-name $VnetName --subnet $AppSubnetName --accelerated-networking true --public-ip-address ${VmName}-pip --network-security-group ''
az vm create --name $VmName --resource-group $RgName  --os-disk-name ${VmName}-osdisk --os-disk-size-gb 64 --storage-sku Premium_LRS --size $AppVmSize  --location $AzLoc  --image $VmImage --admin-username=$VmAdminUsr --nics $NicName --ppg ppg-eun-${Workload}
az vm disk attach --resource-group $RgName --vm-name $VmName --name ${VmName}-datadisk0 --sku Premium_LRS --size 64 --lun 0 --new --caching None

# enable Enable Azure Extension for SAP
az vm aem set -g $RgName -n $VmName

PubIpFqdn=`az network public-ip list --resource-group $RgName| grep fqdn | grep $VmName | awk '{print $2}'| sed 's/.\{2\}$//'| cut -c2-`
# do stuff inside app VM    filesystem creation for HANA https://docs.microsoft.com/en-us/azure/virtual-machines/workloads/sap/sap-hana-high-availability
ssh -oStrictHostKeyChecking=no ${VmAdminUsr}@${PubIpFqdn} << EOF
sudo pvcreate /dev/disk/azure/scsi1/lun0
sudo vgcreate vg_sap /dev/disk/azure/scsi1/lun0
sudo lvcreate -n lv_sap -l +100%FREE vg_sap
sudo mkfs.xfs /dev/mapper/vg_sap-lv_sap
sudo mkdir -p /usr/sap
sudo su -
echo '/dev/mapper/vg_sap-lv_sap /usr/sap   xfs      defaults,nofail,nobarrier      0 2' >> /etc/fstab
mount -a
sed -i 's/ResourceDisk.Format=n/ResourceDisk.Format=y/g' /etc/waagent.conf
sed -i 's/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g' /etc/waagent.conf
sed -i 's/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=20480/g' /etc/waagent.conf
systemctl restart waagent
swapon -s
EOF
