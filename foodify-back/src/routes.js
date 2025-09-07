import express from "express";
import { getStock } from "./stockController.js";
import { addMovement } from "./movementController.js";

const router = express.Router();

router.get("/stock", getStock);
router.post("/movements", addMovement);

export default router;
