#!/bin/sh
# This is what is set to autorun when the SD cards are inserted.
cd $HOME/photos
extractpix 2>&1 | tee -a import_logs/photo.import.log.`date +%F`
sleep 10
