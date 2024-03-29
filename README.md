# Integrate Puppet with Conjur
## Introduction
- This guide demonstrates how Puppet agents can retrieve credentials from Conjur.
- The integration between Puppet and Conjur is established using the Puppet module for Conjur: <https://forge.puppet.com/modules/cyberark/conjur>.
- The demonstration will use 2 Puppet `exec` resource:
  - Run a sql command to show databases using the credentials retrieved from Conjur, and save the output to `/root/<%= $time %>-mysql.log`
  - Run an AWS CLI command to list users using the credentials retrieved from Conjur, and save the output to `/root/<%= $time %>-aws.log`

### Software Versions
- RHEL 8.5
- Puppet 7.14
- Conjur 12.5

### Servers

| Hostname  | Role |
| --- | --- |
| conjur.vx  | Conjur master, Puppet server  |
| foxtrot.vx  | Puppet agent  |
| mysql.vx  | MySQL server  |

# 1. Setup MySQL database
- Setup MySQL database according to this guide: <https://github.com/joetanx/mysql-world_db>

# 2. Setup Conjur master
- Setup Conjur master according to this guide: <https://github.com/joetanx/setup/blob/main/conjur.md>

# 3. Setup Puppet
## 3.1. Setup Puppet server
- Setup Puppet repository, install Puppet server and Hiera package, add firewall rule for Puppet server
```console
yum -y install https://yum.puppetlabs.com/puppet-release-el-8.noarch.rpm
yum -y install puppetserver hiera
firewall-cmd --add-service puppetmaster --permanent && firewall-cmd --reload
```
- Configure Puppet server
```console
cat << EOF >> /etc/puppetlabs/puppet/puppet.conf
[main]
certname = conjur.vx
server = conjur.vx
[server]
dns_alt_names = conjur.vx
EOF
sed -i 's/Xms2g/Xms1g/' /etc/sysconfig/puppetserver
sed -i 's/Xmx2g/Xmx1g/' /etc/sysconfig/puppetserver
```
- Optional - change Java to version 11
  - The Puppet server package installs Java 8 as a dependency
  - If you already have applications on the server using Java 11, this will break your application; I have Jenkins running on Java 11 in my lab
  - Change the `/usr/bin/java` link back to Java 11 after installing Puppet server to resolve this
```console
rm -f /usr/bin/java
ln -s /usr/lib/jvm/jre-11-openjdk-11.0.12.0.7-4.el8.x86_64/bin/java /usr/bin/java
```
- Initialize Puppet server CA and start Puppet server
```console
/opt/puppetlabs/bin/puppetserver ca setup
systemctl enable --now puppetserver
```

## 3.2. Setup Puppet agent
```console
yum -y install https://yum.puppetlabs.com/puppet-release-el-8.noarch.rpm
yum -y install puppet-agent
cat << EOF >> /etc/puppetlabs/puppet/puppet.conf
[main]
certname = foxtrot.vx
server = conjur.vx
EOF
/opt/puppetlabs/bin/puppet resource service puppet ensure=running enable=true
```

## 3.3. Connect Puppet agent to Puppet server
- Check and sign CSR on Puppet server
```console
/opt/puppetlabs/bin/puppetserver ca list
/opt/puppetlabs/bin/puppetserver ca sign --certname foxtrot.vx
```

# 4. Preparatory configurations 
## 4.1. Prepare Conjur configurations
- Install Puppet module for Conjur. Ref: <https://github.com/cyberark/conjur-puppet>
- Load the Conjur policy `puppet-vars.yaml`
  - Creates the policy `puppet` with a same-name layer and a host `demo`
  - The Puppet agent will use the Conjur identity `host/puppet/demo` to retrieve credentials
  - Adds `puppet` layer to `consumers` group for `world_db` and `aws_api` policies
  - The `world_db` and `aws_api` policies are defined in `app-vars.yaml` in <https://github.com/joetanx/setup/blob/main/app-vars.yaml>
> `puppet-vars.yaml` builds on top of `app-vars.yaml` in <https://github.com/joetanx/setup/blob/main/app-vars.yaml>. Loading `puppet-vars.yaml` without having `app-vars.yaml` loaded previously will not work.

```console
/opt/puppetlabs/bin/puppet module install cyberark-conjur
curl -L -o puppet-vars.yaml https://github.com/joetanx/conjur-puppet/raw/main/puppet-vars.yaml
conjur policy load -b root -f puppet-vars.yaml
```
- Clean-up
```console
rm -f puppet-vars.yaml
```

## 4.2. Prepare Puppet manifest
- `conjur-demo.pp` is used to demonstrate how a Puppet manifest file can use the Puppet module for Conjur to fetch secrets and use those secrets in other resources
- `node 'foxtrot.vx' {` specifies the node that the manifest will apply to, change this accordingly to your Puppet agent FQDN
- 2 sets of secrets will be fetched:
  - `world_db/username` and `world_db/password`
  - `aws_api/awsakid` and `aws_api/awssak`
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
  - This assumes that you have setup a MySQL server according to this guide: <https://github.com/joetanx/mysql-world_db>
  - This also assumes that the MySQL client is installed on the Puppet agent node
- The `$awscommand` variable assignment prepares the demonstration AWS CLI command to be used with the `exec` resource
  - This AWS CLI command will:
    - Set the retrieved credentials as environment variables
    - Run the aws iam list-users commands
    - Output it to a file named after the current run time at the `/root` directory
  - Change the AWS CLI command accordingly to your environment
  - This assumes that you have setup a MySQL server according to this guide: <https://github.com/joetanx/mysql-world_db>
  - This also assumes that the MySQL client is installed on the Puppet agent node
- For more details on how to fetch and use secrets from Conjur, refer to the Puppet module for Conjur page: <https://github.com/cyberark/conjur-puppet>
- The command below downloads the manifest file to the default folder for `production` environment, change this accordingly for your Puppet configuration
```console
curl -L -o /etc/puppetlabs/code/environments/production/manifests/conjur-demo.pp https://github.com/joetanx/conjur-puppet/raw/main/conjur-demo.pp
```

## 4.3. Prepare Hiera variables
- The commands below creates the data directory and downloads the Hiera file to a file named after the Puppet agent FQDN
- Change the directory and file name according to your environment
```console
mkdir /etc/puppetlabs/code/environments/production/data/nodes
curl -L -o /etc/puppetlabs/code/environments/production/data/nodes/foxtrot.vx.yaml https://github.com/joetanx/conjur-puppet/raw/main/hiera-config.yaml
```
- Rotate a new API key for the Conjur idenity of the Puppet agent and insert to the Hiera file
```console
NEWAPIKEY=$(conjur host rotate-api-key -i puppet/demo | grep 'New API key' | cut -d ' ' -f 5)
sed -i "s/<insert-new-api-key>/$NEWAPIKEY/" /etc/puppetlabs/code/environments/production/data/nodes/foxtrot.vx.yaml
```
- Retrieve the certificate of your Conjur appliance and insert to the Hiera file
```console
openssl s_client -showcerts -connect conjur.vx:443 </dev/null 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > conjur-certificate.pem
sed -i 's/^/    /' conjur-certificate.pem
sed -i '/<insert-conjur-certificate>/ r conjur-certificate.pem' /etc/puppetlabs/code/environments/production/data/nodes/foxtrot.vx.yaml
sed -i '/<insert-conjur-certificate>/d' /etc/puppetlabs/code/environments/production/data/nodes/foxtrot.vx.yaml
```
- Clean-up
```console
rm -f conjur-certificate.pem
```
- Change any other variables according to your environment

## 4.4 Install AWS CLI and MySQL client on Puppet agent node
- We will use the AWS CLI in the Puppet manifest to demonstrate the AWS API calls
- Setup AWS CLI
```console
yum -y install unzip mysql
curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip
unzip awscliv2.zip
./aws/install
```
- Clean-up
```console
rm -rf aws awscliv2.zip
```

# 5. Run the demonstration
- Request catalog from Puppet agent node
```console
/opt/puppetlabs/bin/puppet agent --test
```
- Verify the run results
```console
[root@foxtrot ~]# ls -l
total 16
-rw-r--r--. 1 root root 6912 Feb  7 15:34 2022-02-07T07:34:24+00:00-aws.log
-rw-r--r--. 1 root root   63 Feb  7 15:34 2022-02-07T07:34:24+00:00-mysql.log
-rw-------. 1 root root 1486 Dec 13 12:17 anaconda-ks.cfg
[root@foxtrot ~]# tail 2022-02-07T07\:34\:24+00\:00-aws.log
        },
        {
            "Path": "/",
            "UserName": "Sensitive [value redacted]",
            "UserId": "Sensitive [value redacted]",
            "Arn": "Sensitive [value redacted]",
            "CreateDate": "Sensitive [value redacted]"
        }
    ]
}
[root@foxtrot ~]# cat 2022-02-07T07\:34\:24+00\:00-mysql.log
Database
information_schema
mysql
performance_schema
sys
world
[root@foxtrot ~]#
```
