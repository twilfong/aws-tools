#!/bin/bash
#
# Give a url for a simplesamlphp identity provider and a username, prompt for a password, and
# retreive a SAML assertion from the identity provider.
#
# URL should take the form: https://MY.SSO.COM/saml/saml2/idp/SSOService.php?spentityid=SOME_SP
#
# Based on https://gist.github.com/borgand/6714584

COOKIEJAR=/tmp/curl-saml-cookies

ssourl=$1
user=${2:-`whoami`}

error () {
  echo $1 1>&2
  exit ${2:-1}
}

HTML=$(curl -L -sS -c ${COOKIEJAR} -b ${COOKIEJAR} -w 'LAST_URL:%{url_effective}' ${ssourl}) ||
    error "Problem connecting to SSO endpoint."

# If cookie token is still good we should get a SAML response
SNIP=$(echo ${HTML} | grep -o 'name=\"SAMLResponse[^>]*value=\"[^\"]*\"') && {
  # Parse SAML Response from snippet and exit
  echo $SNIP | awk -F\" '{print $(NF-1)}'
  exit 0
}

# Otherwise, we need to parse the AUTHURL and AUTHSTATE from the output and login with username and password

AUTHURL=$(echo $HTML | sed -e 's/.*LAST_URL:\(.*\)$/\1/')
AUTHSTATE=$(echo ${HTML} | sed -e 's/.*hidden[^>]*AuthState[^>]*value=[\"'\'']\([^\"'\'']*\)[\"'\''].*/\1/')

# Get password from user
read -s -p "Password: " password
echo > /dev/tty

HTML=$(echo -n "$password" | curl -L -sS -c ${COOKIEJAR} -b ${COOKIEJAR} -w 'LAST_URL:%{url_effective}' \
        --data-urlencode "username=$user" --data-urlencode password@- --data-urlencode \
        "AuthState=${AUTHSTATE}" ${AUTHURL}) || error "Problem connecting to authentication URL."
unset password

# Find form element with SAML Response in HTML output, or exit with error
SNIP=$(echo ${HTML} | grep -o 'name=\"SAMLResponse[^>]*value=\"[^\"]*\"') || 
        error "Problem getting SAML Response string from SSO authentication URL."

# Parse SAML Response from snippet
echo $SNIP | awk -F\" '{print $(NF-1)}'
