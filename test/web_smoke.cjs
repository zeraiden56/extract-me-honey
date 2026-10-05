// Build first, then serve build/web over HTTP. This uses a real Firefox browser.
// npm install --prefix tmp/browser-test --no-audit --no-fund puppeteer-core
// node test/web_smoke.cjs http://127.0.0.1:8080/
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const puppeteer = require(process.env.HONEY_PUPPETEER_PATH || path.resolve(__dirname, '../tmp/browser-test/node_modules/puppeteer-core'));

const url = process.argv[2] || 'http://127.0.0.1:8080/';
const saveKey = 'extract-me-honey-deluxe:v1';
const output = path.resolve(__dirname, '../tmp/web-smoke');
fs.mkdirSync(output, { recursive: true });

async function ready(page) {
  await page.waitForFunction(() => document.getElementById('loading').hidden || document.documentElement.dataset.failed, { timeout: 60000 });
  assert.equal(await page.evaluate(() => document.documentElement.dataset.failed), undefined, 'game failed to start');
}

async function readSave(page) {
  return page.evaluate(() => JSON.parse(Module.honeyReadSave()));
}

async function clickGame(page, x, y) {
  const rect = await page.$eval('#canvas', canvas => {
    const r = canvas.getBoundingClientRect();
    return { x: r.x, y: r.y, width: r.width, height: r.height };
  });
  await page.mouse.click(rect.x + x * rect.width / 1672, rect.y + y * rect.height / 941);
  // SDL dispatches queued mouse events during its next animation frame.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function loadSave(page, state) {
  await page.evaluate((key, value) => localStorage.setItem(key, JSON.stringify(value)), saveKey, state);
  await page.reload({ waitUntil: 'load' });
  await ready(page);
}

(async () => {
  const browser = await puppeteer.launch({ browser: 'firefox', executablePath: process.env.HONEY_FIREFOX || '/usr/bin/firefox', headless: true });
  const errors = [];
  try {
    const page = await browser.newPage();
    await page.setViewport({ width: 1280, height: 850 });
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => {
      if (message.type() === 'error' && !message.text().startsWith('Save ignorado:')) errors.push(message.text());
    });
    await page.goto(url, { waitUntil: 'load' });
    await ready(page);
    let state = await readSave(page);
    assert.equal(state.hives, 1);
    assert.equal(state.honey < 5, true);
    await clickGame(page, 190, 355);
    state = await readSave(page);
    assert.ok(state.honey >= 1.875, 'click reward missing');
    assert.deepEqual(JSON.parse(await page.evaluate(key => localStorage.getItem(key), saveKey)), state, 'click was not persisted');
    const clickedHoney = state.honey;
    await page.reload({ waitUntil: 'load' });
    await ready(page);
    assert.ok((await readSave(page)).honey >= clickedHoney, 'reload lost progress');
    await page.screenshot({ path: path.join(output, 'new-game.png') });

    state = await readSave(page);
    Object.assign(state, { honey: 1e9, hives: 37, pollen: 100, saved_at: Date.now() / 1000 });
    Object.assign(state.perks, { steady_hands: 2, second_wind: 1, bee_ai: 1 });
    await loadSave(page, state);
    await clickGame(page, 1550, 318);
    // This hive costs more than the balance; the next attempt is affordable.
    assert.equal((await readSave(page)).hives, 37);
    state.honey = 1e12;
    await loadSave(page, state);
    await clickGame(page, 1550, 318);
    assert.equal((await readSave(page)).hives, 38, 'hive limit returned in the web build');
    await clickGame(page, 1320, 780);
    assert.equal((await readSave(page)).gloves_level, 1, 'shop input was misplaced');
    await clickGame(page, 1530, 225);
    await clickGame(page, 1300, 725);
    assert.equal((await readSave(page)).perks.rush_capacity, 1, 'perk purchase failed');
    await page.screenshot({ path: path.join(output, 'legacy.png') });

    state = await readSave(page);
    state.run_honey = 250000;
    state.perks.legacy_apiary = 20;
    await loadSave(page, state);
    await clickGame(page, 1530, 225);
    await clickGame(page, 1550, 820);
    state = await readSave(page);
    assert.equal(state.prestige_count, 1);
    assert.equal(state.hives, 21);
    assert.equal(state.perks.bee_ai, 1);

    // Let AbelhIA cross the 12 visible groups, then inspect the autosaved result.
    await page.waitForFunction(started => {
      const saved = JSON.parse(Module.honeyReadSave());
      return saved.saved_at - started >= 15 && saved.honey > 100;
    }, { timeout: 24000 }, state.saved_at);

    // JSON from older saves, offline earnings, and corrupted local storage.
    state = await readSave(page);
    state.honey = state.run_honey = state.lifetime_honey = 0;
    state.hives = 13;
    state.prestige_count = 0;
    Object.keys(state.perks).forEach(key => { state.perks[key] = 0; });
    delete state.perks.bee_ai;
    delete state.perks.rush_capacity;
    state.saved_at = Date.now() / 1000 - 36000;
    await loadSave(page, state);
    state = await readSave(page);
    assert.ok(Math.abs(state.honey - 13 * 28800) < 20, 'offline cap or old-save migration failed');
    assert.equal(state.perks.bee_ai, 0);

    const savedBeforeDemo = await page.evaluate(key => localStorage.getItem(key), saveKey);
    await page.goto(url + '?demo=1', { waitUntil: 'load' });
    await ready(page);
    await clickGame(page, 190, 355);
    assert.equal(await page.evaluate(key => localStorage.getItem(key), saveKey), savedBeforeDemo, 'demo overwrote the save');
    await page.setViewport({ width: 844, height: 390 });
    await clickGame(page, 1530, 225);
    await page.screenshot({ path: path.join(output, 'mobile-landscape.png') });

    await page.evaluate(key => localStorage.setItem(key, '{broken'), saveKey);
    await page.goto(url, { waitUntil: 'load' });
    await ready(page);
    assert.equal((await readSave(page)).hives, 1, 'corrupted save stopped the game');
    assert.deepEqual(errors, [], 'browser errors occurred');
    console.log('PASS: WebAssembly rendering, clicks, purchases, unlimited hives, perks, prestige, automation, saves, offline cap, demo, resize.');
    console.log(`Screenshots: ${output}`);
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
