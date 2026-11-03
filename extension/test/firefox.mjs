import assert from 'node:assert/strict';
import {Builder, By, until} from 'selenium-webdriver';
import firefox from 'selenium-webdriver/firefox.js';
import {createServer} from 'node:http';
import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {root, fixture} from './helpers.mjs';
import {prepareNative, verifyNative, finishNative} from './native-helper.mjs';

if (!process.env.DISPLAY) throw new Error('Run under xvfb-run -a or a desktop display for actual shortcut activation.');
const pkg = JSON.parse(await readFile(join(root,'package.json'),'utf8'));
const html = await fixture('article.html');
const requests = [];
const server = createServer((req,res)=>{
  requests.push(req.url);
  res.writeHead(req.url==='/guides/article'?200:404, {'Content-Type':'text/html'});
  res.end(req.url==='/guides/article'?html:'Not found');
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url = `http://127.0.0.1:${server.address().port}/guides/article`;
const options = new firefox.Options().setBinary(process.env.FIREFOX_BIN || '/usr/bin/firefox')
  .setPreference('browser.shell.checkDefaultBrowser',false)
  .setPreference('browser.startup.homepage','about:blank')
  .setPreference('datareporting.policy.dataSubmissionEnabled',false)
  .setPreference('toolkit.telemetry.enabled',false);
const driverPath = process.env.GECKODRIVER || execFileSync('which',['geckodriver'],{encoding:'utf8'}).trim();
const service = new firefox.ServiceBuilder(driverPath).addArguments('--allow-system-access');
const native = await prepareNative();
if(native) service.setEnvironment(native.env);
let driver;
try {
  driver = await new Builder().forBrowser('firefox').setFirefoxOptions(options).setFirefoxService(service).build();
  if(native) {
    // Point only this disposable browser's directory service at the test manifests.
    await driver.setContext('chrome');
    await driver.executeScript(function(directory) {
      const provider = {getFile(property,persistent) {
        if(property!=='XREUserNativeManifests') return null;
        persistent.value=true;
        const file=Components.classes['@mozilla.org/file/local;1'].createInstance(Components.interfaces.nsIFile);
        file.initWithPath(directory); return file;
      }, QueryInterface:ChromeUtils.generateQI(['nsIDirectoryServiceProvider'])};
      window.gopherTestDirectoryProvider=provider;
      Services.dirsvc.registerProvider(provider);
      try {Services.dirsvc.undefine('XREUserNativeManifests');} catch {}
    },join(native.root,'firefox'));
    await driver.setContext('content');
  }
  await driver.manage().window().setRect({width:1280,height:1000});
  const addon = await driver.installAddon(join(root,'artifacts',`gopher-reader-${pkg.version}-firefox.zip`),true);
  assert.equal(addon,'gopher-reader@rafael-minuesa.github.io');
  await driver.get(url);
  await driver.wait(until.elementLocated(By.id('details')),10000);
  const original = await driver.getWindowHandle();
  const count = requests.length;
  const windowId = execFileSync('xdotool',['search','--onlyvisible','--class','[Ff]irefox'],{encoding:'utf8'}).trim().split('\n').at(-1);
  execFileSync('xdotool',['windowfocus','--sync',windowId]);
  execFileSync('xdotool',['key','--clearmodifiers','alt+shift+0']);
  await driver.wait(async()=> (await driver.getAllWindowHandles()).length > 1,15000);
  const handles = await driver.getAllWindowHandles();
  const reading = handles.find(handle=>handle!==original);
  await driver.switchTo().window(reading);
  await driver.wait(until.elementIsVisible(await driver.wait(until.elementLocated(By.id('reading')),10000)),10000);
  assert.equal(await driver.findElement(By.id('title')).getText(),'A quieter way to read');
  assert.match(await driver.findElement(By.id('content')).getText(), /Keep the structure/);
  assert.doesNotMatch(await driver.findElement(By.id('content')).getText(),/HIDDEN SECRET|SECRET FORM|SECRET INPUT/);
  assert.equal(requests.length,count,'No source content is fetched again');
  assert.match(await driver.findElement(By.css('.link-reference')).getText(), /\[1\]/);
  if(native) {
    await driver.findElement(By.id('native-open')).click();
    await driver.wait(async()=> (await driver.findElement(By.id('status')).getText()).includes('Saved locally and opened'),15000);
    await verifyNative(native,new URL(await driver.getCurrentUrl()).searchParams.get('id'));
    await driver.switchTo().window(original);
    execFileSync('xdotool',['windowfocus','--sync',windowId]);
    execFileSync('xdotool',['key','--clearmodifiers','alt+shift+0']);
    await driver.wait(async()=> (await driver.getAllWindowHandles()).length===3,15000);
    const second=(await driver.getAllWindowHandles()).find(handle=>handle!==original && handle!==reading);
    await driver.switchTo().window(second);
    await driver.wait(until.elementIsVisible(await driver.wait(until.elementLocated(By.id('reading')),10000)),10000);
    await driver.findElement(By.id('native-open')).click();
    await driver.wait(async()=> (await driver.findElement(By.id('status')).getText()).includes('Saved locally and opened'),15000);
    await verifyNative(native,new URL(await driver.getCurrentUrl()).searchParams.get('id'));
    await driver.close(); await driver.switchTo().window(reading);
  } else {
    await driver.findElement(By.id('native-open')).click();
    await driver.wait(until.elementIsVisible(await driver.wait(until.elementLocated(By.id('error')),10000)),10000);
    assert.match(await driver.findElement(By.id('error')).getText(),/Install the Linux app/);
  }
  await driver.findElement(By.css('[data-mode="page"]')).click();
  assert.match(await driver.findElement(By.id('content')).getText(),/RELATED PAGE SIDEBAR/);
  await driver.findElement(By.css('[data-mode="links"]')).click();
  assert.match(await driver.findElement(By.id('content')).getText(),/reference guide/);
  await driver.findElement(By.css('[data-mode="article"]')).click();
  await driver.findElement(By.id('save')).click();
  await driver.wait(async()=> (await driver.findElement(By.id('save')).getText())==='Saved',5000);
  await driver.navigate().refresh();
  await driver.wait(until.elementLocated(By.id('content')),10000);
  await driver.wait(async()=> (await driver.findElement(By.id('save')).getAttribute('aria-pressed'))==='true',5000);
  await driver.findElement(By.id('find-open')).click();
  await driver.findElement(By.id('find')).sendKeys('text');
  await driver.wait(async()=> (await driver.findElements(By.css('mark'))).length>=2,5000);
  await driver.findElement(By.id('find-close')).click();
  await mkdir(join(root,'artifacts'),{recursive:true});
  await writeFile(join(root,'artifacts/firefox-reader.png'),Buffer.from(await driver.takeScreenshot(),'base64'));
  await driver.switchTo().window(original);
  await driver.executeScript("const p=document.createElement('p');p.textContent='Firefox refresh text.';document.querySelector('article').append(p);");
  await driver.switchTo().window(reading);
  await driver.findElement(By.id('refresh')).click();
  await driver.wait(async()=> (await driver.findElement(By.id('content')).getText()).includes('Firefox refresh text.'),5000);
  console.log('Firefox: temporary package installation, actual shortcut/activeTab conversion, safe extraction, three views, bookmarks, reload, find, and refresh passed.');
} finally {
  if (driver) await driver.quit();
  await finishNative(native);
  server.close();
}
