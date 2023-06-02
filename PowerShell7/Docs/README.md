# Scripts (API version 19.8):
## Modules: 
* dell.networker.psm1
    * PowerShell7 module that covers basic interaction with the Networker REST API
    * Functions
        * connect-nwapi: method to connect to the REST API
        * get-jobs: method to query for jobs
        * new-monitor: method to monitor mounting a session, or recovery
        * get-protectedvms: method to query for virtual machine clients
        * get-backups: method to query for image level backups
        * new-vmmount: method to mound a virtual machine backup for recovery
        * new-recover: method to recover a mounted virtual machine backup
    * Tasks
        * Task-01: example query for failed jobs
        * Task-02: example of redirected file level recovery from an image level backup