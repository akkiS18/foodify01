import pkg from "pg";
import Memcached from "memcached";
import dotenv from "dotenv";

dotenv.config();
const { Pool } = pkg;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

export const cache = new Memcached(
  process.env.MEMCACHED_URL || "127.0.0.1:11211"
);
