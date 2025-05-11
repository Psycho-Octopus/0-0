const boards = ['all', 'chat', 'memes', 'news'];
const boardNav = document.getElementById('boardNav');

boards.forEach((bName) => {
  let link = document.createElement('a');
  link.href = `/${bName}`;
  link.textContent = `/${bName}/`;
  boardNav.appendChild(link);
});

const naughtyWords = ['badword1', 'badword2', 'offensive', 'profanity'];
function filterBadWords(text) {
  return text.split(' ').map(w =>
    naughtyWords.includes(w.toLowerCase()) ? '*'.repeat(w.length) : w
  ).join(' ');
}

const socket = new WebSocket(`ws://${location.host}/ws${window.location.pathname}`);
const chatLog = document.getElementById('chat');
const form = document.getElementById('messageForm');
const textBox = document.getElementById('textBox');
const imageUpload = document.getElementById('imageUpload');
const userCountDisplay = document.getElementById('activeUsers');

function currentTime() {
  const now = new Date();
  return now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function showMessage(payload) {
  const msgDiv = document.createElement('div');
  msgDiv.className = 'message';

  if (payload.image) {
    let img = document.createElement('img');
    img.src = payload.image;
    msgDiv.appendChild(img);
  }

  const msgWrapper = document.createElement('div');
  msgWrapper.className = 'text';

  if (payload.text) {
    const p = document.createElement('p');
    p.textContent = payload.text;
    msgWrapper.appendChild(p);
  }

  const time = document.createElement('span');
  time.className = 'timestamp';
  time.textContent = payload.timestamp || currentTime();
  msgWrapper.appendChild(time);

  msgDiv.appendChild(msgWrapper);
  chatLog.appendChild(msgDiv);
  chatLog.scrollTop = chatLog.scrollHeight;
}

socket.addEventListener('message', (e) => {
  try {
    const msg = JSON.parse(e.data);
    if (msg.type === 'active_users') {
      userCountDisplay.textContent = `Active Users: ${msg.count}`;
    } else if (msg.type === 'history') {
      msg.messages.forEach(showMessage);
    } else {
      showMessage(msg);
    }
  } catch (err) {
    console.error("Error parsing message", err);
  }
});

form.addEventListener('submit', (e) => {
  e.preventDefault();

  let rawText = textBox.value.trim();
  let file = imageUpload.files[0];
  if (!rawText && !file) return;

  let cleanText = filterBadWords(rawText);
  let payload = {
    text: cleanText,
    timestamp: currentTime()
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
});
