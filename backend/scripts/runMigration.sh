#!/bin/bash
# Quick migration runner script
# Run this from Render shell: bash scripts/runMigration.sh

echo "🚀 Starting MongoDB Migration..."
echo "================================"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# Run the migration
echo ""
echo "Running fixNullGeofences.js..."
node scripts/fixNullGeofences.js

echo ""
echo "✅ Migration script completed!"
