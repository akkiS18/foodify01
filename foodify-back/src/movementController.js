import { pool, cache } from "./db.js";
import { io } from "./index.js";

export async function addMovement(req, res) {
  try {
    const { branch_id, movement_type, products = [] } = req.body;

    console.log("📥 Incoming payload:", req.body);

    if (!branch_id || !movement_type || products.length === 0) {
      console.error("❌ Invalid payload:", req.body);
      return res.status(400).json({ error: "Invalid payload" });
    }

    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      let createdMovements = [];

      for (const p of products) {
        const { product_id, qty } = p;
        console.log("➡️ Processing product:", product_id, "qty:", qty);

        // 🔎 productni olish
        const prodRes = await client.query(
          `SELECT id, name FROM products WHERE id = $1`,
          [product_id]
        );
        const product = prodRes.rows[0];

        if (!product) {
          console.error("❌ Product not found:", product_id);
          throw new Error(`Product not found: ${product_id}`);
        }

        console.log("✅ Found product:", product);

        // 🔎 ingredientlarni olish
        const ingRes = await client.query(
          `
          SELECT ingredient_id, qty
          FROM product_ingredients
          WHERE product_id = $1
          `,
          [product_id]
        );

        console.log(`🔎 Ingredients for ${product.name}:`, ingRes.rows);

        if (ingRes.rows.length === 0) {
          console.warn(`⚠️ No ingredients found for product ${product_id}`);
        }

        // 🔄 ingredientlar bo‘yicha OUT yozish
        for (const ing of ingRes.rows) {
          const usedQty = Number(ing.qty) * qty;

          if (isNaN(usedQty)) {
            console.error("❌ NaN detected:", {
              ing_qty: ing.qty,
              product_qty: qty,
              product_id,
              ingredient_id: ing.ingredient_id,
            });
            throw new Error("NaN qty in inventory_movements");
          }

          console.log(
            `📦 Inserting movement → ingredient: ${ing.ingredient_id}, qty: ${usedQty}`
          );

          const result = await client.query(
            `
            INSERT INTO inventory_movements
              (branch_id, ingredient_id, qty, movement_type, created_at)
            VALUES ($1, $2, $3, $4, NOW())
            RETURNING id, branch_id, ingredient_id, qty, movement_type, created_at
            `,
            [branch_id, ing.ingredient_id, usedQty, movement_type]
          );

          const movement = result.rows[0];
          createdMovements.push(movement);

          console.log("✅ Movement created:", movement);

          // 🗑️ cache invalidation
          cache.del(`stock:${branch_id}:*`, (err) => {
            if (err) console.error("Cache delete error:", err);
          });
        }

        // ✅ faqat product tugagandan keyin emit qilamiz
        io.to(`branch:${branch_id}`).emit("order:new", {
          product_id: product.id,
          product_name: product.name,
          qty,
          branch_id,
          created_at: new Date().toISOString(),
        });
      }

      await client.query("COMMIT");

      console.log("🎉 Transaction committed:", createdMovements);

      res.json({ status: "success", movements: createdMovements });
    } catch (err) {
      await client.query("ROLLBACK");
      console.error("❌ Transaction error:", err.message, err.stack);
      res.status(500).json({ error: err.message });
    } finally {
      client.release();
    }
  } catch (err) {
    console.error("❌ addMovement fatal error:", err.message, err.stack);
    res.status(500).json({ error: "Internal Server Error" });
  }
}
