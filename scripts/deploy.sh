#! /bin/bash

set -euo pipefail

# We need some infos
PRIVATE_KEY=${PRIVATE_KEY:-}
RPC_URL=${RPC_URL:-}
CHAIN_ID=${CHAIN_ID:-}
OCWEBSITE_FACTORY_ADDRESS=${OCWEBSITE_FACTORY_ADDRESS:-}
STATIC_FRONTEND_PLUGIN_ADDRESS=${STATIC_FRONTEND_PLUGIN_ADDRESS:-}
OCWEB_ADMIN_PLUGIN_ADDRESS=${OCWEB_ADMIN_PLUGIN_ADDRESS:-}
ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-}
if [ -z "$PRIVATE_KEY" ]; then
  echo "PRIVATE_KEY env var is not set"
  exit 1
fi
if [ -z "$RPC_URL" ]; then
  echo "RPC_URL env var is not set"
  exit 1
fi
if [ -z "$CHAIN_ID" ]; then
  echo "CHAIN_ID env var is not set"
  exit 1
fi
if [ -z "$OCWEBSITE_FACTORY_ADDRESS" ]; then
  echo "OCWEBSITE_FACTORY_ADDRESS env var is not set"
  exit 1
fi
if [ -z "$STATIC_FRONTEND_PLUGIN_ADDRESS" ]; then
  echo "STATIC_FRONTEND_PLUGIN_ADDRESS env var is not set"
  exit 1
fi
if [ -z "$OCWEB_ADMIN_PLUGIN_ADDRESS" ]; then
  echo "OCWEB_ADMIN_PLUGIN_ADDRESS env var is not set"
  exit 1
fi
if [ -z "$ETHERSCAN_API_KEY" ]; then
  echo "ETHERSCAN_API_KEY env var is not set"
  exit 1
fi

# check that forge is installed
if ! command -v forge &> /dev/null
then
    echo "forge could not be found. Please install foundry (toolkit for Ethereum application development)"
    exit
fi

# Compute the plugin root folder (which is the parent folder of this script)
ROOT_FOLDER=$(cd $(dirname $(readlink -f $0)) && cd .. && pwd)


#
# Create an OCWebsite
#

exec 5>&1
OUTPUT="$(PRIVATE_KEY=$PRIVATE_KEY \
  npx ocweb --rpc $RPC_URL --skip-tx-validation mint --factory-address $OCWEBSITE_FACTORY_ADDRESS $CHAIN_ID about-me-theme | tee >(cat - >&5))"

# Get the address of the OCWebsite
OCWEBSITE_ADDRESS=$(echo "$OUTPUT" | sed -n 's/.*New OCWebsite smart contract: \(0x[a-fA-F0-9]\{40\}\).*/\1/p')
echo "Extracted OCWEBSITE_ADDRESS: $OCWEBSITE_ADDRESS"

#
# Build and upload the admin frontend and the main frontend
#

# Go to the admin frontend folder
cd $ROOT_FOLDER/admin
# Build the admin frontend
npm run build

# Go to the frontend folder
cd $ROOT_FOLDER/frontend
# Build the frontend
npm run build

# Make a temporary folder where we mix both admin and frontend
cd $ROOT_FOLDER
rm -Rf $ROOT_FOLDER/dist
mkdir -p dist
mkdir -p dist/themes/about-me
cp -R admin/dist/* dist/themes/about-me
cp -R frontend/dist/index.html frontend/dist/logo.svg frontend/dist/assets dist

# Upload the admin frontend
PRIVATE_KEY=$PRIVATE_KEY \
WEB3_ADDRESS=web3://$OCWEBSITE_ADDRESS:$CHAIN_ID \
npx ocweb --rpc $RPC_URL --skip-tx-validation upload dist/* /


#
# Build the plugin
# 

FORGE_CREATE_OPTIONS=
if [ "$CHAIN_ID" != "31337" ] && [ "$CHAIN_ID" != "3335" ]; then
  FORGE_CREATE_OPTIONS="--verify"
fi
forge create --broadcast --private-key $PRIVATE_KEY $FORGE_CREATE_OPTIONS \
--rpc-url $RPC_URL \
src/ThemeAboutMePlugin.sol:ThemeAboutMePlugin \
--constructor-args $OCWEBSITE_ADDRESS $STATIC_FRONTEND_PLUGIN_ADDRESS $OCWEB_ADMIN_PLUGIN_ADDRESS \


