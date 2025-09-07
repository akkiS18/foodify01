import { pool, cache } from "./db.js";

export async function getStock(req, res) {
  try {
    const { branch_id, page = 1, limit = 20, search = "" } = req.query;
    const offset = (page - 1) * limit;

    const cacheKey = `stock:${branch_id}:${page}:${limit}:${search}`;

    // 1) Cache tekshiramiz
    cache.get(cacheKey, async (err, cached) => {
      if (err) {
        console.error("Memcached get error:", err);
      }

      if (cached) {
        // cache topildi → shu javobni qaytaramiz
        return res.json(JSON.parse(cached));
      }

      // 2) Agar cache bo‘lmasa, DB dan o‘qish
      const result = await pool.query(
        `
        SELECT 
          sl.ingredient_id, 
          i.name AS ingredient_name, 
          sl.qty, 
          sl.branch_id
        FROM stock_levels sl
        JOIN ingredients i ON i.id = sl.ingredient_id
        WHERE sl.branch_id = $1
          AND i.name ILIKE $2
        ORDER BY i.name
        LIMIT $3 OFFSET $4
        `,
        [branch_id, `%${search}%`, limit, offset]
      );

      const countResult = await pool.query(
        `
        SELECT COUNT(*) 
        FROM stock_levels sl
        JOIN ingredients i ON i.id = sl.ingredient_id
        WHERE sl.branch_id = $1
          AND i.name ILIKE $2
        `,
        [branch_id, `%${search}%`]
      );

      const response = {
        data: result.rows,
        pagination: {
          page: Number(page),
          limit: Number(limit),
          total: Number(countResult.rows[0].count),
        },
      };

      // 3) Javobni cache’ga yozamiz (60 soniya)
      cache.set(cacheKey, JSON.stringify(response), 60, (err) => {
        if (err) console.error("Memcached set error:", err);
      });

      // 4) Javobni qaytarish
      res.json(response);
    });
  } catch (err) {
    console.error("getStock error:", err);
    res.status(500).json({ error: "Internal Server Error" });
  }
}
