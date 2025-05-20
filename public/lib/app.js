window.addEventListener('DOMContentLoaded', function() {
      alert('Please be appropriate and consider what you are sending before submiting your message.');

      // Email validation for login page
      const emailInput = document.querySelector('input[type="email"]');
      if (emailInput) {
        emailInput.addEventListener('input', function() {
          const email = emailInput.value.trim();
          const valid = /^[a-zA-Z0-9._%+-]+@edtools\.psd401\.net$/.test(email);
          emailInput.setCustomValidity(valid ? '' : 'Please use your @edtools.psd401.net email');
        });
      }
    });

    const naughtyWords = ['badword1', 'badword2', 'offensive', 'profanity'];
    function filterBadWords(text) {
      return text.split(' ').map(w =>
        naughtyWords.includes(w.toLowerCase()) ? '*'.repeat(w.length) : w
      ).join(' ');
    }

    const protocol = location.protocol === 'https:' ? 'wss' : 'ws';
    const socket = new WebSocket(`${protocol}://${location.host}/ws`);

    const chatLog = document.getElementById('chat');
    const form = document.getElementById('messageForm');
    const textBox = document.getElementById('textBox');
    const imageUpload = document.getElementById('imageUpload');
    const userCountDisplay = document.getElementById('activeUsers');

    let username = 'anon1'; // This should be set by the server in a real app

    // Store message reactions in-memory (keyed by messageId)
    const messageReactions = {};

    function currentTime() {
      const now = new Date();
      return now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }

    // Generate a simple message id based on timestamp and username
    function generateMessageId(payload) {
      return (
        (payload.timestamp || currentTime()) +
        '_' +
        (payload.username || '') +
        '_' +
        (payload.text || '') +
        '_' +
        (payload.image ? payload.image.substring(0, 10) : '')
      );
    }

    function showMessage(payload) {
      // If message is pooped to death, show that instead
      if (payload.pooped) {
        payload.text = '💩 to death';
        payload.image = null;
      }

      const msgDiv = document.createElement('div');
      msgDiv.className = 'message';

      // Generate a message id for reaction tracking
      const messageId = payload.id || generateMessageId(payload);
      msgDiv.dataset.messageId = messageId;

      // Username
      const usernameDiv = document.createElement('div');
      usernameDiv.className = 'username';
      usernameDiv.textContent = payload.username;
      msgDiv.appendChild(usernameDiv);

      // Image
      if (payload.image) {
        let img = document.createElement('img');
        img.src = payload.image;
        msgDiv.appendChild(img);
      }

      // Message text
      const msgWrapper = document.createElement('div');
      msgWrapper.className = 'text';
      if (payload.text) {
        const p = document.createElement('p');
        if (payload.pooped) {
          p.textContent = payload.text;
          p.className = 'pooped-message';
        } else {
          p.textContent = payload.text;
        }
        msgWrapper.appendChild(p);
      }

      // Timestamp
      const time = document.createElement('span');
      time.className = 'timestamp';
      time.textContent = payload.timestamp || currentTime();
      msgWrapper.appendChild(time);

      msgDiv.appendChild(msgWrapper);

      // --- Reaction buttons ---
      const reactionDiv = document.createElement('div');
      reactionDiv.style.marginLeft = 'auto';
      reactionDiv.style.display = 'flex';
      reactionDiv.style.alignItems = 'center';
      reactionDiv.style.gap = '8px';

      // Like button with count
      const likeBtn = document.createElement('button');
      likeBtn.type = 'button';
      likeBtn.className = 'like-btn';
      likeBtn.style.cursor = 'pointer';
      likeBtn.innerHTML = `🔥 <span>${payload.likes || 0}</span>`;
      likeBtn.title = "Like this message";

      // Dislike button with count
      const dislikeBtn = document.createElement('button');
      dislikeBtn.type = 'button';
      dislikeBtn.className = 'dislike-btn';
      dislikeBtn.style.cursor = 'pointer';
      dislikeBtn.innerHTML = `💩 <span>${payload.dislikes || 0}</span>`;
      dislikeBtn.title = "Dislike (poop) this message";

      // Like handler
      likeBtn.onclick = function () {
        socket.send(JSON.stringify({
          type: 'reaction',
          reaction: 'like',
          id: messageId
        }));
      };

      // Dislike handler
      dislikeBtn.onclick = function () {
        socket.send(JSON.stringify({
          type: 'reaction',
          reaction: 'dislike',
          id: messageId
        }));
      };

      reactionDiv.appendChild(likeBtn);
      reactionDiv.appendChild(dislikeBtn);

      msgDiv.appendChild(reactionDiv);

      chatLog.appendChild(msgDiv);
      chatLog.scrollTop = chatLog.scrollHeight;
    }

    // Update reactions for a message
    function updateReactions(id, likes, dislikes, pooped) {
      // Find the message div
      const msgDiv = chatLog.querySelector(`[data-message-id="${id}"]`);
      if (!msgDiv) return;

      // Update like/dislike counts on buttons
      const likeBtn = msgDiv.querySelector('.like-btn');
      const dislikeBtn = msgDiv.querySelector('.dislike-btn');
      if (likeBtn) {
        const span = likeBtn.querySelector('span');
        if (span) span.textContent = likes;
      }
      if (dislikeBtn) {
        const span = dislikeBtn.querySelector('span');
        if (span) span.textContent = dislikes;
      }

      // If pooped, replace message text with styled big text
      if (pooped) {
        const textDiv = msgDiv.querySelector('.text');
        if (textDiv) {
          textDiv.innerHTML = '<p class="pooped-message">💩 to death</p>';
        }
        // Remove image if present
        const img = msgDiv.querySelector('img');
        if (img) img.remove();
      }
    }

    const sendBtn = document.getElementById('sendBtn');
    let throttled = false;
    let throttleTimeout = null;

    socket.addEventListener('message', (e) => {
      try {
        const msg = JSON.parse(e.data);
        if (msg.type === 'disable_tab') {
          // Disable chat UI but do not close the tab
          document.body.innerHTML = `
            <div style="display:flex;justify-content:center;align-items:center;height:100vh;flex-direction:column;">
              <h2 style="color:#BB86FC;">This tab has been disabled</h2>
              <p style="color:#eee;">Another tab is already open for this account.<br>Close this tab or refresh to try again.</p>
            </div>
          `;
          socket.close();
          return;
        }
        if (msg.type === 'rate_limit') {
          throttled = true;
          if (sendBtn) {
            sendBtn.textContent = 'Throttled (wait 5s)';
            sendBtn.disabled = true;
            sendBtn.classList.add('sending');
          }
          textBox.disabled = true;
          clearTimeout(throttleTimeout);
          throttleTimeout = setTimeout(() => {
            throttled = false;
            if (sendBtn) {
              sendBtn.textContent = 'Send';
              sendBtn.disabled = false;
              sendBtn.classList.remove('sending');
            }
            textBox.disabled = false;
          }, 5000);
          return;
        }
        if (msg.type === 'active_users') {
          userCountDisplay.textContent = `Active Users: ${msg.count}`;
        } else if (msg.type === 'history') {
          msg.messages.forEach(showMessage);
        } else if (msg.type === 'reaction_update') {
          updateReactions(msg.id, msg.likes, msg.dislikes, msg.pooped);
        } else {
          showMessage(msg);
        }
      } catch (err) {
        console.error("Error parsing message", err);
      }
    });

    form.addEventListener('submit', (e) => {
      e.preventDefault();
      if (throttled) return;

      let rawText = textBox.value.trim();
      let file = imageUpload.files[0];
      if (!rawText && !file) return;

      let cleanText = filterBadWords(rawText);
      let payload = {
        text: cleanText,
        timestamp: currentTime(),
        username: username // Send the logged-in user's username with the message
      };

      if (file) {
        const reader = new FileReader();
        reader.onload = function () {
          payload.image = reader.result;
          socket.send(JSON.stringify(payload));
        };
        reader.readAsDataURL(file);
      } else {
        socket.send(JSON.stringify(payload));
      }

      textBox.value = '';
      imageUpload.value = '';
      charCounter.textContent = '0/500';
      textBox.focus();
    });

    // Character counter for text box
    const charCounter = document.getElementById('charCounter');
    textBox.addEventListener('input', function() {
      charCounter.textContent = `${textBox.value.length}/500`;
      if (textBox.value.length > 500) {
        charCounter.style.color = '#ff4d4d';
        sendBtn.disabled = true;
      } else {
        charCounter.style.color = '#888';
        if (!throttled) sendBtn.disabled = false;
      }
    });

    // Submit form on Enter key (without Shift)
    textBox.addEventListener('keydown', function(e) {
      if (e.key === 'Enter' && !e.shiftKey) {
        e.preventDefault();
        if (!sendBtn.disabled) form.requestSubmit();
      }
    });
