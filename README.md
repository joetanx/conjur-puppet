### Software Versions
- RHEL 8.5
- Puppet 7.14
- Conjur 12.4

# 1. Setup MySQL database
- Setup MySQL database according to this guide: https://github.com/joetanx/mysql-world_db
# 2. Setup Conjur master
- Setup Conjur master according to this guide: https://github.com/joetanx/conjur-master
# 3. Setup Puppet
## 3.1. Setup Puppet server
```console
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum -y install https://yum.puppetlabs.com/puppet-release-el-8.noarch.rpm
yum -y install puppetserver hiera
firewall-cmd --add-service puppetmaster --permanent && firewall-cmd --reload
sed -i "s/Xms2g/Xms1g/" /etc/sysconfig/puppetserver
sed -i "s/Xmx2g/Xmx1g/" /etc/sysconfig/puppetserver
/opt/puppetlabs/bin/puppetserver ca setup
systemctl enable --now puppetserver
```
## 3.2. Setup Puppet agent
```console
yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum -y install https://yum.puppetlabs.com/puppet-release-el-8.noarch.rpm
yum -y install puppet-agent
cat << EOF >> /etc/puppetlabs/puppet/puppet.conf
[main]
certname = jenkins.vx
server = conjur.vx
EOF
/opt/puppetlabs/bin/puppet resource service puppet ensure=running enable=true
```
## 3.3. Connect Puppet agent to Puppet server
- Check and sign CSR on Puppet server
```console
/opt/puppetlabs/bin/puppetserver ca list
/opt/puppetlabs/bin/puppetserver ca sign --certname jenkins.vx
```
## 3.4. Prepare Conjur configurations
- Install Puppet module for Conjur. Ref: https://github.com/cyberark/conjur-puppet
- Load the Conjur policy `puppet-vars.yaml`
  - The policy `puppet` is create with a same-name layer with a host `demo`
  - The Puppet agent will be using the Conjur identity of `host/puppet/demo`
  - The `puppet` layer is added to `consumers` group for `world_db` and `aws_api` policies
  - The `world_db` and `aws_api` policies are defined in `app-vars.yaml` in https://github.com/joetanx/conjur-master
> `puppet-vars.yaml` builds on top of `app-vars.yaml` in https://github.com/joetanx/conjur-master. Loading `puppet-vars.yaml` without having `app-vars.yaml` loaded previously will not work.
```console
/opt/puppetlabs/bin/puppet module install cyberark-conjur
curl -L -o puppet-vars.yaml https://github.com/joetanx/conjur-puppet/raw/main/puppet-vars.yaml
conjur policy load -b root -f puppet.yaml
```
## Work-In-Progress
