// server.js
const express = require('express');
const app = express();
const http = require('http').createServer(app);
const io = require('socket.io')(http);
const path = require('path');

app.use(express.static(path.join(__dirname, 'public')));

// In-memory rate limiter and message history
const messageRateLimits = new Map();
const messageHistory = [];

io.on('connection', (socket) => {
  console.log('A user connected:', socket.id);

  // Send recent message history to the newly connected user
  socket.emit('chat history', messageHistory);

  // Initialize rate limit tracking
  messageRateLimits.set(socket.id, []);

  socket.on('chat message', (msg) => {
    const now = Date.now();
    const timestamps = messageRateLimits.get(socket.id) || [];

    // Filter to only messages within the last 10 seconds
    const recentTimestamps = timestamps.filter(ts => now - ts < 10000);

    if (recentTimestamps.length >= 5) {
      socket.emit('rate limit', 'You are sending messages too fast. Please slow down.');
      return;
    }

    // Store the timestamp
    recentTimestamps.push(now);
    messageRateLimits.set(socket.id, recentTimestamps);

    // Store the message in history (max 10)
    messageHistory.push(msg);
    if (messageHistory.length > 10) {
      messageHistory.shift();
    }

    // Broadcast the message
    io.emit('chat message', msg);
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
    messageRateLimits.delete(socket.id);
  });
});

http.listen(3000, () => {
  console.log('Hosting on http://localhost:3000');
});
