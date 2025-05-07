#!/bin/sh
# Script to capture what's being downloaded from alx.sh
echo "Capturing content from alx.sh..."
curl -v https://alx.sh > alx_content.txt
echo "Content saved to alx_content.txt"

echo "Capturing content with curl user agent..."
curl -v -A "curl" https://alx.sh > alx_curl_agent.txt
echo "Content saved to alx_curl_agent.txt"

echo "Trying to see what happens when piped to sh..."
curl -v https://alx.sh | tee alx_piped.sh
echo "Content saved to alx_piped.sh"
