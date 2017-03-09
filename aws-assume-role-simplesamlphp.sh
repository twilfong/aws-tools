#!/bin/bash
#
# Get AWS API Key by using `aws sts assume-role-with-saml` and get-saml-assertion-from-simplesamlphp.sh
# Export commands will echo to stdout. Use eval to export to environment.
#
# Example:
#     eval `aws-assume-role-simplesamlphp.sh ACCOUNT_ALIAS USER`
#
# Based on https://gist.github.com/borgand/6714584

account=${1:-default}
user=${2:-`whoami`}
role=$3

# Edit the values below based on simpleSAMLphp and AWS setup
case $account in
alias2)
    ssourl='https://mysso2.example.com/saml/saml2/idp/SSOService.php?spentityid=aws'
    arn=arn:aws:iam::123456789012
    idp=saml-provider/myOtheridp
    role=role/${3:-powerUser}
    ;;
*)
    ssourl='https://mysso.example.com/saml/saml2/idp/SSOService.php?spentityid=aws'
    arn=arn:aws:iam::XXXXXXXXXXXX
    idp=saml-provider/myDefaultidp
    role=role/${3:-User}
    ;;
esac

DIR="$(dirname "$0")"
SAMLRESPONSE=`$DIR/get-saml-assertion-from-simplesamlphp.sh "$ssourl" "$user"`

CREDS=( $(aws sts assume-role-with-saml --role-arn $arn:$role --principal-arn $arn:$idp \
    --saml-assertion "$SAMLRESPONSE" --output text --query 'Credentials.{id:AccessKeyId,secret:SecretAccessKey}') ) ||
        echo "Problem getting credentials from AWS AssumeRoleWithSaml API call" 1>&2

if [ "$CREDS" ]; then
    echo export AWS_ACCESS_KEY_ID="${CREDS[0]}"
    echo export AWS_SECRET_ACCESS_KEY="${CREDS[1]}"
fi
