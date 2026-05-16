# WLST script to create a WebLogic domain with Admin Server + Managed Server
# Run as oracle user:
#   /opt/oracle/middleware/oracle_common/common/bin/wlst.sh /opt/oracle/scripts/02-create-domain.py

DOMAIN_NAME   = 'base_domain'
DOMAIN_HOME   = '/opt/oracle/domains/' + DOMAIN_NAME
WLS_HOME      = '/opt/oracle/middleware/wlserver'
ADMIN_PORT    = 7001
MANAGED_PORT  = 7003
WLS_PASSWORD  = 'Welcome1#'

print('Creating domain: ' + DOMAIN_HOME)

readTemplate(WLS_HOME + '/common/templates/wls/wls.jar')

# Admin Server
cd('Servers/AdminServer')
set('ListenAddress', '')
set('ListenPort', ADMIN_PORT)

# Admin credentials
cd('/')
cd('Security/' + DOMAIN_NAME + '/User/weblogic')
cmo.setPassword(WLS_PASSWORD)

# Create Managed Server
cd('/')
create('ssi-demo-ms', 'Server')
cd('Servers/ssi-demo-ms')
set('ListenAddress', '')
set('ListenPort', MANAGED_PORT)

setOption('OverwriteDomain', 'true')
writeDomain(DOMAIN_HOME)
closeTemplate()

print('Domain created at: ' + DOMAIN_HOME)
print('Admin Server port : ' + str(ADMIN_PORT))
print('Managed Server port: ' + str(MANAGED_PORT))
print('Username: weblogic  /  Password: ' + WLS_PASSWORD)
