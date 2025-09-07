1. Clone repo
```bash
git clone https://github.com/akkiS18/foodify01.git
cd foodify01
```

2. Run backend
```bash
cd backend
npm install
npm run dev
```

3. PostgreSQL
```bash
createdb demo
psql -d demo -f schema.sql
psql -d demo -f seed.sql
```
