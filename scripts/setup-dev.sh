#!/bin/bash
set -e

echo "=========================================="
echo "NESF Core: Developer Environment Setup"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Step 1: Dependencies
echo -e "${BLUE}→ Installing API dependencies...${NC}"
cd api
npm install
cd ..

echo -e "${BLUE}→ Installing Flutter dependencies...${NC}"
cd app
flutter pub get
cd ..

# Step 2: Database
echo -e "${BLUE}→ Starting Postgres via Docker Compose...${NC}"
docker-compose up -d
sleep 3  # Wait for DB to start

# Step 3: Database setup
echo -e "${BLUE}→ Migrating database schema...${NC}"
cd api
export DATABASE_URL="postgres://nesf_core:dev-password-local@localhost:5432/nesf_core_dev"
npm run migrate

echo -e "${BLUE}→ Seeding database with initial data...${NC}"
npm run seed

# Step 4: Summary
echo ""
echo -e "${GREEN}✓ Setup complete!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Start the API (in one terminal):"
echo "   cd api"
echo "   npm start"
echo ""
echo "2. Start the Flutter app (in another terminal):"
echo "   cd app"
echo "   flutter run --dart-define=API_BASE=http://10.0.2.2:4000  # Android emulator"
echo "   flutter run --dart-define=API_BASE=http://localhost:4000 # macOS/iOS simulator"
echo ""
echo "3. Run tests:"
echo "   cd api"
echo "   npm run test:e2e  # End-to-end tests"
echo "   npm run test:media # Media privacy tests"
echo ""
echo "Admin credentials (from seed):"
echo "  Email: biki@nesportsfoundation.in"
echo "  Password: ChangeMe@123"
echo ""
