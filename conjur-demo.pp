node 'foxtrot.vx' {

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
    $conjurawsakid = Deferred(conjur::secret, ['aws_api/awsakid', {
        appliance_url => lookup('conjur::appliance_url'),
        account => lookup('conjur::account'),
        authn_login => lookup('conjur::authn_login'),
        authn_api_key => lookup('conjur::authn_api_key'),
        ssl_certificate => lookup('conjur::ssl_certificate')
        }]
    )
    $conjurawssak = Deferred(conjur::secret, ['aws_api/awssak', {
        appliance_url => lookup('conjur::appliance_url'),
        account => lookup('conjur::account'),
        authn_login => lookup('conjur::authn_login'),
        authn_api_key => lookup('conjur::authn_api_key'),
        ssl_certificate => lookup('conjur::ssl_certificate')
        }]
    )
    $mysqlcommand = Deferred('inline_epp', [
        '/usr/bin/mysql --host=mysql.vx --user=<%= $username.unwrap %> --password=<%= $password.unwrap %> -e \'SHOW DATABASES;\' > /root/<%= $time %>-mysql.log',
        {
            'username' => $conjurusername,
            'password' => $conjurpassword,
            'time' => Timestamp.new().strftime('%Y-%m-%dT%H:%M:%S%:z')
        }
    ])
    $awscommand = Deferred('inline_epp', [
        '/usr/bin/bash -c \'export AWS_ACCESS_KEY_ID=<%= $awsakid.unwrap %> && export AWS_SECRET_ACCESS_KEY=<%= $awssak.unwrap %> && /usr/local/bin/aws iam list-users > /root/<%= $time %>-aws.log\'',
        {
            'awsakid' => $conjurawsakid,
            'awssak' => $conjurawssak,
            'time' => Timestamp.new().strftime('%Y-%m-%dT%H:%M:%S%:z')
        }
    ])
    exec { 'mysql-run':
        command => $mysqlcommand
    }
    exec { 'awscli-run':
        command => $awscommand,
        environment => 'AWS_DEFAULT_REGION=ap-southeast-1'
    }
}
