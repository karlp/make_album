#!/bin/sh
cd $HOME/photos
extractpix 2>&1 | tee -a import_logs/photo.import.log.`date +%F`
sleep 10
