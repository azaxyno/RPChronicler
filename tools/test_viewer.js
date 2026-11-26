// Checks StoryViewer.html against the fixture SavedVariables file.
//   node tools/test_viewer.js        (needs Playwright with Chromium)
// Loads tools/fixture/RPChronicler.lua and a Screenshots folder with the
// fixture's shot files, then opens every story and checks its title,
// pictures and timeline, and that the page logged no errors.
const fs = require("fs"), path = require("path"), os = require("os");
const { chromium } = require("playwright");
const root = path.resolve(__dirname, "..");
const lua = path.join(root, "tools", "fixture", "RPChronicler.lua");
const JPG = Buffer.from("/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAIAAgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDOooor5s+4P//Z", "base64");

(async () => {
  const shots = fs.mkdtempSync(path.join(os.tmpdir(), "rpc-shots-"));
  const names = new Set();
  for (const m of fs.readFileSync(lua, "utf8").matchAll(/\["file"\] = "([^"]+)"/g)) names.add(m[1]);
  for (const n of names) fs.writeFileSync(path.join(shots, n + ".jpg"), JPG);

  const browser = await chromium.launch();
  const page = await browser.newPage();
  const errors = [];
  page.on("pageerror", e => errors.push(String(e)));
  // The page also tries ../../../Screenshots next to the game; that path
  // doesn't exist here, so those misses are expected.
  page.on("requestfailed", r => { if (!/\/Screenshots\/WoWScrnShot_/.test(r.url())) errors.push("failed to load " + r.url().slice(0, 120)); });
  page.on("console", m => { if (m.type() === "error" && !/ERR_FILE_NOT_FOUND/.test(m.text())) errors.push(m.text()); });
  await page.goto("file://" + path.join(root, "StoryViewer.html"));
  await page.setInputFiles("#luaInput", lua);
  await page.setInputFiles("#shotInput", shots);
  await page.waitForSelector("#list li", { timeout: 5000 });
  const items = await page.$$("#list li");
  const want = ["Chronicle of Ragefire Chasm: Fire, Crabs, and Lazy Goblins", "Salt Wind over Durotar"];
  const got = [];
  let fail = 0;
  for (let i = 0; i < items.length; i++) {
    await (await page.$$("#list li"))[i].click();
    await page.waitForTimeout(300);
    const title = (await page.textContent("#reader h1")).trim();
    const imgs = await page.$$eval("#reader .story img", a => a.filter(x => x.complete && x.naturalWidth > 0).length);
    const ticks = await page.$$eval("#tl .tl-tick", a => a.length);
    got.push(title);
    console.log("story:", title, "| pictures:", imgs, "| timeline marks:", ticks);
    if (imgs < 1) { console.log("  FAIL: no picture shown"); fail++; }
    if (ticks < 1) { console.log("  FAIL: no timeline"); fail++; }
    // 0.6.4: loot names in their quality color with a drawn icon
    if (/Ragefire/.test(title)) {
      const loot = await page.$$eval("#reader .story .item", a => a.map(x => x.textContent + "=" + x.style.color + (x.querySelector("svg") ? "+icon" : "")));
      console.log("  items:", loot.join(", "));
      if (loot.length < 2 || !loot.every(x => /rgb\(30, 255, 0\)\+icon$/.test(x))) { console.log("  FAIL: items not colored with icons"); fail++; }
      if (process.env.SHOT) await page.screenshot({ path: process.env.SHOT, fullPage: false });
    }
  }
  for (const t of want) if (!got.includes(t)) { console.log("FAIL: missing story", t); fail++; }
  if (errors.length) { console.log("FAIL: page errors", errors); fail++; }
  await browser.close();
  fs.rmSync(shots, { recursive: true, force: true });
  console.log(fail ? fail + " check(s) failed" : "all checks passed");
  process.exit(fail ? 1 : 0);
})();
