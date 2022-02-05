node 'jenkins.vx' {

    $conjurusername = Deferred(conjur::secret, ['world_db/username', {
        appliance_url => lookup('conjur::appliance_url'),
        account => lookup('conjur::account'),
        authn_login => lookup('conjur::authn_login'),
        authn_api_key => lookup('conjur::authn_api_key'),
        ssl_certificate => lookup('conjur::ssl_certificate')
        }]
    )
    $conjurpassword = Deferred(conjur::secret, ['world_db/password', {
        appliance_url => lookup('conjur::appliance_url'),
        account => lookup('conjur::account'),
        authn_login => lookup('conjur::authn_login'),
        authn_api_key => lookup('conjur::authn_api_key'),
        ssl_certificate => lookup('conjur::ssl_certificate')
        }]
    )
    $mysqlcommand = Deferred('inline_epp', [
        '/usr/bin/mysql --host=mysql.vx --user=<%= $username.unwrap %> --password=<%= $password.unwrap %> -e \'SHOW DATABASES;\' > /root/<%= $time %>.log',
        {
            'username' => $conjurusername,
            'password' => $conjurpassword,
            'time' => Timestamp.new().strftime('%Y-%m-%dT%H:%M:%S%:z')
        }
    ])
    exec { 'mysql-run':
        command => $mysqlcommand,
        require => Notify['verify']
    }
    notify { 'verify':
        message => $mysqlcommand
    }
}