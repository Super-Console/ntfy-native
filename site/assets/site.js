'use strict';

// This demo is deliberately local: no API, permission prompt, or real notification.
const demoButton = document.querySelector('#demo-send');
const messageList = document.querySelector('#demo-messages');
const demoStatus = document.querySelector('#demo-status');
const samples = [
  { title: '消息到了', body: '从一行命令，到菜单栏。就这么简单。', tag: 'hello' },
  { title: '构建通过', body: '所有步骤已完成，可以放心合上终端了。', tag: 'build' },
  { title: '备份完成', body: '又一份安心，送到你的 Mac。', tag: 'backup' },
];
let sampleIndex = 0;
demoButton.addEventListener('click', () => {
  const sample = samples[sampleIndex % samples.length];
  sampleIndex += 1;
  const article = document.createElement('article');
  article.className = 'message new-message';
  const heading = document.createElement('div');
  const title = document.createElement('h3');
  const time = document.createElement('time');
  const body = document.createElement('p');
  const tag = document.createElement('span');
  title.textContent = sample.title;
  time.textContent = '刚刚';
  body.textContent = sample.body;
  tag.textContent = sample.tag;
  tag.className = 'message-tag mono';
  heading.append(title, time);
  article.append(heading, body, tag);
  messageList.prepend(article);
  while (messageList.children.length > 3) messageList.lastElementChild.remove();
  messageList.scrollTop = 0;
  demoStatus.textContent = `已模拟 ${sampleIndex} 条消息 · 没有发送网络请求`;
});

const copyButton = document.querySelector('#copy-command');
const copyStatus = document.querySelector('#copy-status');
const command = 'curl \\\n    -H "Title: Task complete" \\\n    -d "All done. Take a break." \\\n    "https://ntfy.sh/<your-random-topic>"';
copyButton.addEventListener('click', async () => {
  try {
    if (!navigator.clipboard || !window.isSecureContext) throw new Error('Clipboard unavailable');
    await navigator.clipboard.writeText(command);
    copyStatus.textContent = '已复制。运行前请替换 Topic；不会自动执行。';
  } catch {
    copyStatus.textContent = '无法访问剪贴板，请选中上方命令手动复制。';
    const range = document.createRange();
    range.selectNodeContents(document.querySelector('#curl-command'));
    const selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
  }
});
