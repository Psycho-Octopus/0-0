// server.js
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http);
const path = require('path');

app.use(express.static(path.join(__dirname, 'public')));

// In-memory rate limiter and message history
const messageRateLimits = new Map();
const messageHistory = [];  // <-- Corrected line here

io.on('connection', (socket) => {
  console.log('A user connected:', socket.id);

  // Send recent message history to the newly connected user
  socket.emit('chat history', messageHistory);

  // Initialize rate limit tracking for each user
  messageRateLimits.set(socket.id, { lastMessageTime: 0 });

  socket.on('chat message', (msg) => {
    const now = Date.now();
    const userRateLimit = messageRateLimits.get(socket.id);

    // Check if 60 seconds have passed since the last message
    if (now - userRateLimit.lastMessageTime < 10000) {
      socket.emit('rate limit', 'You can only send 1 message per minute.');
      return;
    }

    // Store the timestamp of this message
    userRateLimit.lastMessageTime = now;
    messageRateLimits.set(socket.id, userRateLimit);

    // Store the message in history (max 10 messages)
    messageHistory.push(msg);
    if (messageHistory.length > 10) {
      messageHistory.shift(); // Remove the oldest message if more than 10
    }

    // Broadcast the message to all users
    io.emit('chat message', msg);
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
    messageRateLimits.delete(socket.id); // Remove user from the rate-limiting map
  });
});

const PORT = process.env.PORT || 3000;
http.listen(PORT, () => {
  console.log(`Hosting on http://localhost:${PORT}`);
});
