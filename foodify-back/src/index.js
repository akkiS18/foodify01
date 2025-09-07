import express from "express";
import http from "http";
import { Server } from "socket.io";
import cors from "cors";
import dotenv from "dotenv";
import router from "./routes.js";

dotenv.config();
const app = express();

app.use(express.json());
app.use(
  cors({
    origin: ["http://localhost:5500", "http://127.0.0.1:5500"],
    credentials: true,
  })
);
app.use("/api", router);

const server = http.createServer(app);
export const io = new Server(server, {
  cors: {
    origin: ["http://localhost:5500", "http://127.0.0.1:5500"],
    credentials: true,
  },
});

io.on("connection", (socket) => {
  // 1) Client branch(lar)ga qo'shilsin
  // Frontend "join" event yuboradi: { branches: [branch_id1, branch_id2] }
  socket.on("join", ({ branches = [] }) => {
    branches.forEach((b) => {
      if (b) socket.join(`branch:${b}`);
    });
    socket.emit("joined", { rooms: branches.map((b) => `branch:${b}`) });
  });

  // Agar foydalanuvchi chiqib ketsa
  socket.on("leave", ({ branches = [] }) => {
    branches.forEach((b) => socket.leave(`branch:${b}`));
  });

  socket.on("disconnect", () => {
    // optional: log
  });
});

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
