1. Clone repo

git clone https://github.com/akkiS18/foodify01.git
cd foodify01

2. Run backend

cd backend
npm install
npm run dev

3. PostgreSQL

createdb demo
psql -d demo -f schema.sql
psql -d demo -f seed.sql
