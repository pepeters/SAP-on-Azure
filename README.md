# SAP-on-Azure
Azure cloud shell script for SAP on Azure, these are just samples not intended for productive usage,
please use as is

script provides automated setup von APP/DB including a vnet plus subnets for APP/DB; includes PPG, accelerated networking, write accelerator for DB, filesystem preparation for HANA
no availability sets or zones are used here
no jumpbox plus separate vnet, needs to be added if necessary

download the script
adjust the parameters like subscription, Azure region, VM type, IP adress, naming conventions eG according your needs
upload to your Azure cloud shell
chmod +x nameofthescript.sh
setup ssh of not already done, in Azure Cloud Shell: ssh-keygen -m PEM -t rsa -b 4096
