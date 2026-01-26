#!/bin/bash

# Package Lambda function for deployment
echo "Packaging Lambda function..."

# Clean up old package
rm -f whi_handler.zip

# Create the zip file with just the handler
zip whi_handler.zip whi_handler.py

echo "Lambda package created: whi_handler.zip"
echo "Size: $(du -h whi_handler.zip | cut -f1)"