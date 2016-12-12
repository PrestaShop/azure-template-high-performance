#!/usr/bin/python

import sys,os
from azure.storage.blob import BlockBlobService

blob_service = BlockBlobService(account_name=str(sys.argv[1]), account_key=str(sys.argv[2]))

blob_service.delete_container('keys')
