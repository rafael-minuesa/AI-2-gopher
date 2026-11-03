import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readdir, readFile, rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createConnection} from 'node:net';

// A complete package is installed in temporary XDG directories. HOME is untouched.
export async function prepareNative() {
  if (!process.env.GOPHER_NATIVE_PACKAGE) return null;
  if (!process.env.DBUS_SESSION_BUS_ADDRESS) throw new Error('Native tests require dbus-run-session.');
  const root = await mkdtemp(join(tmpdir(), 'gopher-native-browser-'));
  const env = {...process.env, XDG_CONFIG_HOME:join(root,'config space %'),
    XDG_DATA_HOME:join(root,'data space %'), XDG_BIN_HOME:join(root,'bin space %'), XDG_RUNTIME_DIR:join(root,'run'),
    GOPHER_FIREFOX_HOST_DIR:join(root,'firefox','native-messaging-hosts')};
  await mkdir(env.XDG_RUNTIME_DIR,{mode:0o700});
  execFileSync('tar',['-xzf',process.env.GOPHER_NATIVE_PACKAGE,'-C',root]);
  const packageName = (await readdir(root)).find(name=>name.startsWith('ai-2-gopher-'));
  execFileSync('bash',[join(root,packageName,'install.sh'),'--no-register'],{env,stdio:'pipe'});
  const version = (await readFile(join(root,packageName,'VERSION'),'utf8')).trim();
  const bundle = join(env.XDG_DATA_HOME,'ai-2-gopher',version);
  return {root,env,bundle,installer:join(root,packageName,'install.sh'),helper:join(bundle,'gopher_reader_companion'),app:join(bundle,'ai-2-gopher')};
}

export function gopher(selector) {
  return new Promise((resolve,reject)=>{
    const chunks=[];
    const socket=createConnection({host:'127.0.0.1',port:7070},()=>socket.write(selector+'\r\n'));
    socket.setTimeout(5000,()=>socket.destroy(new Error('Gopher timeout')));
    socket.on('data',chunk=>chunks.push(chunk)); socket.on('error',reject);
    socket.on('end',()=>resolve(Buffer.concat(chunks).toString('utf8')));
  });
}

async function until(check) {
  for(let i=0;i<100;i++) { if(await check()) return; await new Promise(resolve=>setTimeout(resolve,100)); }
  throw new Error('Native app did not finish navigation');
}
async function filesUnder(directory) {
  const files=[];
  for(const entry of await readdir(directory,{withFileTypes:true})) {
    const file=join(directory,entry.name);
    if(entry.isDirectory()) files.push(...await filesUnder(file));
    else if(entry.name.endsWith('.json')) files.push(file);
  }
  return files;
}

export async function verifyNative(native,id,expected='A quieter way to read') {
  assert.match(id,/^[a-f0-9-]{36}$/);
  const menu=await gopher('/page/'+id);
  assert.match(menu,/0Read article\t\/text\//);
  assert.match(menu,/hOriginal page \(browser\)\tURL:http/);
  assert.ok(menu.includes(expected));
  const text=await gopher('/text/'+id+'/article');
  assert.ok(text.includes(expected));
  assert.ok(text.endsWith('\r\n.\r\n'),'Actual Gopher framing');
  await until(async()=>{
    const files=[...await filesUnder(native.env.XDG_CONFIG_HOME),...await filesUnder(native.env.XDG_DATA_HOME)];
    for(const file of files) {
      if(file.includes('NativeMessagingHosts')) continue;
      if((await readFile(file,'utf8')).includes('/page/'+id)) return true;
    }
    return false;
  });
  const windows=execFileSync('xdotool',['search','--onlyvisible','--name','^AI-2 Gopher$'],{encoding:'utf8'}).trim().split('\n');
  assert.equal(windows.length,1,'Handoffs must reuse the same app window');
  if(process.env.GOPHER_NATIVE_SCREENSHOT) {
    execFileSync('import',['-window',windows[0],process.env.GOPHER_NATIVE_SCREENSHOT]);
  }
  const saved=JSON.parse(await readFile(join(native.env.XDG_DATA_HOME,'gopher-reader','pages',id+'.json'),'utf8'));
  assert.ok(saved.article.includes(expected));
  if(!native.reinstalled) {
    // Reinstalling an existing version must also work while its binaries run.
    execFileSync('bash',[native.installer,'--no-register'],{env:native.env,stdio:'pipe'});
    native.reinstalled=true;
  }
}

export async function finishNative(native) {
  if (!native) return;
  try {execFileSync(native.helper,['--stop'],{env:native.env,stdio:'pipe'});} catch {}
  const processes=execFileSync('ps',['-eo','pid=,args='],{encoding:'utf8'}).split('\n');
  for(const line of processes) {
    const match=line.trim().match(/^(\d+)\s+(.*)$/);
    if(match && (match[2]===native.app || match[2].startsWith(native.app+' '))) {
      try {process.kill(Number(match[1]),'SIGTERM');} catch {}
    }
  }
  await rm(native.root,{recursive:true,force:true});
}
