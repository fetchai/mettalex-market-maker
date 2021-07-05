#!/bin/sh

chmod +x on_cloud.py
FILENAME=`./on_cloud.py`
echo "created file at cloud/${FILENAME}.json"
echo "uploading file on gcloud bucket"
gsutil cp ./cloud/${FILENAME}.json gs://abi-bytecode-test-bucket
