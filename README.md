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
cat << EOF >> /etc/puppetlabs/puppet/puppet.conf
[main]
certname = conjur.vx
server = conjur.vx
[server]
dns_alt_names = conjur.vx
EOF
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
# 4. Preparatory configurations 
## 4.1. Prepare Conjur configurations
- Install Puppet module for Conjur. Ref: https://github.com/cyberark/conjur-puppet
- Load the Conjur policy `puppet-vars.yaml`
  - Creates the policy `puppet` is with a same-name layer and a host `demo`
  - The Puppet agent will use the Conjur identity `host/puppet/demo` to retrieve credentials
  - Adds `puppet` layer to `consumers` group for `world_db` and `aws_api` policies
  - The `world_db` and `aws_api` policies are defined in `app-vars.yaml` in https://github.com/joetanx/conjur-master
> `puppet-vars.yaml` builds on top of `app-vars.yaml` in https://github.com/joetanx/conjur-master. Loading `puppet-vars.yaml` without having `app-vars.yaml` loaded previously will not work.
```console
/opt/puppetlabs/bin/puppet module install cyberark-conjur
curl -L -o puppet-vars.yaml https://github.com/joetanx/conjur-puppet/raw/main/puppet-vars.yaml
conjur policy load -b root -f puppet-vars.yaml
```
- Clean-u
```console
rm -f puppet-vars.yaml
```
## 4.2. Prepare Puppet manifest
- `conjur-demo.pp` is used to demonstrate how a Puppet manifest file can use the Puppet module for Conjur to fetch secrets and use those secrets in other resources
- `node 'jenkins.vx' {` specifies the node that the manifest will apply to, change this accordingly to your Puppet agent FQDN
- 2 secrets will be fetch: `world_db/username` and `world_db/password`
- The Syntax to use the function provided by the Puppet module for Conjur is:
```console
    $<puppet-variable-name> = Deferred(conjur::secret, ['<conjur-variable-name>', {
        appliance_url => lookup('conjur::appliance_url'),
        account => lookup('conjur::account'),
        authn_login => lookup('conjur::authn_login'),
        authn_api_key => lookup('conjur::authn_api_key'),
        ssl_certificate => lookup('conjur::ssl_certificate')
        }]
```
- The `lookup('conjur::<puppet-variable>')` function uses variables that are stored in Hiera, which is created in the next section
- The `$mysqlcommand` variable assignment prepares the demonstration MySQL command to be used with the `exec` resource
  - This MySQL command will login to the MySQL server and do a `SHOW DATABASES` command, then output it to a file named after the current run time at the `/root` directory
  - Change the MySQL command accordingly to your environment
  - This assumes that you have setup a MySQL server according to this guide: https://github.com/joetanx/mysql-world_db
  - This also assumes that the MySQL client is installed on the Puppet agent node
- For more details on how to fetch and use secrets from Conjur, refer to the Puppet module for Conjur page: https://github.com/cyberark/conjur-puppet
- The command below downloads the manifest file to the default folder for `production` environment, change this accordingly for your Puppet configuration
```console
curl -L -o /etc/puppetlabs/code/environments/production/manifests/conjur-demo.pp https://github.com/joetanx/conjur-puppet/raw/main/conjur-demo.pp
```
## 4.3. Prepare Hiera variables
- The commands below creates the data directory and downloads the Hiera file to a file named after the Puppet agent FQDN
- Change the directory and file name according to your environment
```console
mkdir /etc/puppetlabs/code/environments/production/data/nodes
curl -L -o /etc/puppetlabs/code/environments/production/data/nodes/jenkins.vx.yaml https://github.com/joetanx/conjur-puppet/raw/main/hiera-config.yaml
```
- Rotate a new API key for the Conjur idenity of the Puppet agent and insert to the Hiera file
```console
NEWAPIKEY=$(conjur host rotate-api-key -i puppet/demo | grep 'New API key' | cut -d ' ' -f 5)
sed -i "s/<insert-new-api-key>/$NEWAPIKEY/" /etc/puppetlabs/code/environments/production/data/nodes/jenkins.vx.yaml
```
- Retrieve the certificate of your Conjur appliance and insert to the Hiera file
```console
openssl s_client -showcerts -connect conjur.vx:443 </dev/null 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > conjur-certificate.pem
sed -i 's/^/    /' conjur-certificate.pem
sed -i '/<insert-conjur-certificate>/ r conjur-certificate.pem' /etc/puppetlabs/code/environments/production/data/nodes/jenkins.vx.yaml
sed -i '/<insert-conjur-certificate>/d' /etc/puppetlabs/code/environments/production/data/nodes/jenkins.vx.yaml
```
- Clean-up
```console
rm -f conjur-certificate.pem
```
- Change any other variables according to your environment
# 5. Run the demonstration
- Request catalog from Puppet agent node
```console
/opt/puppetlabs/bin/puppet agent --test
```
- Verify the run results
```console

```
