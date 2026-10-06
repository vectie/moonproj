#!/usr/bin/env python3
"""Bounded real-native product catalog/document checks; all services/providers offline."""
import argparse, copy, hashlib, http.client, io, json, os, signal, socket, subprocess, tempfile, time, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
EXPECTED = {'moonproj','moonbook','moonclaw','moontown','moondesk','moongate','moonrobo','moonmoon','moonfish','mooncast','moonchat','moonfind','moonflow','moonfort','moonlib','moonmold','moonpoly','moonedit','moonleaf','moonvis'}
ENROLLED = {'moonproj','moonbook','moonclaw','moontown','moondesk','moongate','moonrobo','moonmoon','moonfish'}

def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0)); return s.getsockname()[1]

def request(port, path, cookie=None, method='GET', payload=None):
    c = http.client.HTTPConnection('127.0.0.1', port, timeout=10)
    headers = {'Cookie': cookie} if cookie else {}
    if payload is not None: headers['Content-Type']='application/json'
    try:
        c.request(method, path, body=json.dumps(payload) if payload is not None else None, headers=headers)
        r=c.getresponse(); raw=r.read(); return r.status, dict((k.lower(),v) for k,v in r.getheaders()), raw
    finally: c.close()

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--binary',required=True); ap.add_argument('--catalog',required=True); ap.add_argument('--documents',required=True); ap.add_argument('--launcher'); ap.add_argument('--baseline',action='store_true'); ap.add_argument('--output',required=True); a=ap.parse_args()
    binary=Path(a.binary).resolve(); checks=[]
    def check(label, condition):
        if not condition: raise AssertionError(label)
        checks.append(label)
    with tempfile.TemporaryDirectory(prefix='moonproj-packaged-products-') as temp:
        root=Path(temp); resources=root/'Resources'; resources.mkdir(); (resources/'public').mkdir(); (resources/'public/index.html').write_text('<html><body>packaged UI fixture</body></html>')
        (resources/'config').mkdir(); catalog_path=resources/'config/moonsuite-engineering.json'; original=Path(a.catalog).read_bytes(); catalog_path.write_bytes(original)
        import shutil
        shutil.copytree(a.documents,resources/'product-documents'); workspace=root/'workspace';workspace.mkdir();cwd=root/'unrelated-cwd';cwd.mkdir();bindir=root/'bin';bindir.mkdir()
        catalog=json.loads(original); port=4173 if a.launcher else free_port(); offline=free_port()
        if a.launcher:
            with socket.socket() as s:s.bind(('127.0.0.1',port))
            (bindir/'moonproj-company-service').write_text('#!/bin/sh\nexit 42\n');(bindir/'moonproj-company-service').chmod(0o755)
            (bindir/'moonproj-company-gateway').symlink_to(binary)
            command=['sh',str(Path(a.launcher).resolve())]
        else:
            command=[str(binary),'--host','127.0.0.1','--port',str(port),'--service-port',str(offline),'--public-dir',str(resources/'public'),'--moonsuite-workspace-root',str(workspace)]
        env={**os.environ,'PATH':str(bindir)+os.pathsep+os.environ['PATH'],'LEPUSA_RESOURCE_DIR':str(resources),'LEPUSA_APP_DATA_DIR':str(root/'appdata'),'MOONPROJ_PRODUCT_CATALOG':str(catalog_path),'MOONPROJ_PRODUCT_DOCUMENT_ROOT':str(resources/'product-documents'),'MOONSUITE_WORKSPACE_ROOT':str(workspace),'MOONPROJ_SERVICE_TOKEN':'synthetic-token','MOONPROJ_ACTOR_SIGNING_SECRET':'synthetic-actor-secret','MOONPROJ_SESSION_SECRET':'synthetic-session-secret','MOONPROJ_DEV_USER':'fixture','MOONPROJ_DEV_PASSWORD':'synthetic-password','MOONPROJ_DESKTOP_ACTOR':'desktop-owner','MOONCLAW_DAEMON_URI':f'http://127.0.0.1:{offline}'}
        if a.launcher:
            # Prove launcher itself supplies resource configuration.
            for key in ['MOONPROJ_PRODUCT_CATALOG','MOONPROJ_PRODUCT_DOCUMENT_ROOT','MOONSUITE_WORKSPACE_ROOT']:env.pop(key,None)
            workspace=root/'appdata/workspaces'
        log=open(Path(a.output).with_suffix('.process.log'),'w')
        p=subprocess.Popen(command,cwd=cwd,env=env,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
        try:
            deadline=time.monotonic()+20
            while True:
                try:
                    status,_,_=request(port,'/api/session')
                    if status==401:break
                except OSError:pass
                if p.poll() is not None or time.monotonic()>deadline:raise AssertionError('gateway did not start')
                time.sleep(.1)
            status,_,_=request(port,'/api/moonsuite/products');check('no-session catalog is 401',status==401)
            status,_,_=request(port,'/api/moonsuite/products/moonproj/documents/prd');check('no-session document is 401',status==401)
            status,headers,_=request(port,'/');check('supported desktop page establishes session',status==200 and 'set-cookie' in headers)
            cookie=headers['set-cookie'].split(';')[0]
            check('tampered session is 401',request(port,'/api/moonsuite/products',cookie+'bad')[0]==401)
            status,_,body=request(port,'/api/moonsuite/products',cookie)
            if a.baseline:
                result={'expected_red':status!=200,'catalog_http_status':status,'checks':checks,'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'reason':'Baseline lacks local product registry route; upstream is deliberately offline'}
                assert result['expected_red'];Path(a.output).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result));return
            check('catalog succeeds with company, MoonClaw and provider offline',status==200)
            check('gateway readiness does not depend on company health',request(port,'/ready')[0]==200 and request(port,'/health')[0]==503)
            payload=json.loads(body);rows={r['id']:r for r in payload['products']}
            check('exact twenty active product set and exclusions',set(rows)==EXPECTED and len(payload['products'])==20)
            check('exact existing nine audit subset',{k for k,v in rows.items() if v['engineering_target']}==ENROLLED)
            check('MoonFish retains configured path and unknown origin',rows['moonfish']['repository']=={'path':'moonfish','url':None,'revision':None,'source_kind':'configured','availability':'missing'})
            check('four unresolved repositories stay null',all(rows[i]['repository'] is None for i in ['moonpoly','moonedit','moonleaf','moonvis']))
            check('server missing repositories explicitly reported',all(r['repository'] is None or r['repository']['availability']=='missing' for r in rows.values()))
            check('GET does not infer company records',all(r['company_project_id'] is None for r in rows.values()))
            for row in rows.values():
                for doc in row['documents']:
                    status,headers,raw=request(port,doc['url'],cookie)
                    check(row['id']+' actual packaged PRD bytes and MIME/disposition',status==200 and raw==(resources/'product-documents'/doc['path']).read_bytes() and hashlib.sha256(raw).hexdigest()==doc['sha256'] and headers['content-type']=='application/vnd.openxmlformats-officedocument.wordprocessingml.document' and headers['content-disposition']==f'attachment; filename="{doc["file_name"]}"')
            status,headers,raw=request(port,'/api/moonsuite/products/moonproj/documents/prd',cookie,method='HEAD');check('HEAD uses document MIME without body',status==200 and not raw and headers['content-type'].endswith('document'))
            for path in ['/api/moonsuite/products/unknown/documents/prd','/api/moonsuite/products/moonproj/documents/unknown','/api/moonsuite/products/moonproj/documents/%2e%2e','/api/moonsuite/products/../documents/prd','/api/moonsuite/products/moonproj/documents/prd/extra']:
                check('unknown/traversal declared route 404 '+path,request(port,path,cookie)[0]==404)
            check('product reads cannot mutate via POST',request(port,'/api/moonsuite/products',cookie,method='POST',payload={})[0]==405)
            reversed_catalog=copy.deepcopy(catalog);reversed_catalog['products'].reverse();catalog_path.write_text(json.dumps(reversed_catalog));status,_,body=request(port,'/api/moonsuite/products',cookie);check('reordered catalog preserves IDs and documents',status==200 and {r['id'] for r in json.loads(body)['products']}==EXPECTED and request(port,'/api/moonsuite/products/moonproj/documents/prd',cookie)[0]==200);catalog_path.write_bytes(original)
            for label,changed in [('malformed','{'),('wrong schema',json.dumps({**catalog,'schema':'wrong'})),('duplicate identity',json.dumps({**catalog,'products':catalog['products']+[catalog['products'][0]]}))]:
                catalog_path.write_text(changed);status,_,body=request(port,'/api/moonsuite/products',cookie);check(label+' catalog visibly invalid',status==503 and json.loads(body)['code']=='product_catalog_invalid'); check(label+' catalog does not prevent gateway readiness',request(port,'/ready')[0]==200)
            catalog_path.unlink();status,_,body=request(port,'/api/moonsuite/products',cookie);check('missing catalog visibly unavailable',status==503 and json.loads(body)['code']=='product_catalog_missing');check('missing catalog does not prevent gateway readiness',request(port,'/ready')[0]==200);catalog_path.write_bytes(original)
            doc=resources/'product-documents/MoonProj_PRD.docx';saved=doc.read_bytes()
            edited=io.BytesIO()
            with zipfile.ZipFile(io.BytesIO(saved)) as source, zipfile.ZipFile(edited,'w',compression=zipfile.ZIP_DEFLATED) as target:
                for item in source.infolist():
                    data=source.read(item.filename)
                    if item.filename=='word/document.xml': data=data.replace(b'</w:body>',b'<w:p><w:r><w:t>Local fixture edit</w:t></w:r></w:p></w:body>')
                    target.writestr(item,data)
            doc.write_bytes(edited.getvalue());status,_,raw=request(port,'/api/moonsuite/products/moonproj/documents/prd',cookie)
            check('ordinary declared DOCX edit remains downloadable without a hash gate',status==200 and raw==edited.getvalue() and hashlib.sha256(raw).digest()!=hashlib.sha256(saved).digest())
            doc.unlink()
            status,_,body=request(port,'/api/moonsuite/products',cookie);missing=next(x for x in json.loads(body)['products'] if x['id']=='moonproj')['documents'][0]
            check('missing PRD stays declared and unavailable',status==200 and missing['availability']=='missing' and missing['url'] is None and request(port,'/api/moonsuite/products/moonproj/documents/prd',cookie)[0]==404)
            outside=root/'outside.docx';outside.write_bytes(saved);doc.symlink_to(outside);check('declared symlink cannot escape document root',request(port,'/api/moonsuite/products/moonproj/documents/prd',cookie)[0]==404);doc.unlink();doc.write_bytes(saved)
            workspace.mkdir(parents=True,exist_ok=True);(workspace/'moonfish').mkdir();status,_,body=request(port,'/api/moonsuite/products',cookie);fish=next(x for x in json.loads(body)['products'] if x['id']=='moonfish');check('MoonFish runtime presence is checked on serving machine',fish['repository']['availability']=='present')
            audit={'project':'mooncast','branch':'main','version':'1.0','tag':'v1.0'};status,_,body=request(port,'/api/moonsuite/engineering/audits',cookie,method='POST',payload=audit);check('inventory-only target cannot start existing audit',status==400 and 'not registered' in json.loads(body)['error'])
            audit['project']='moonfish';status,_,body=request(port,'/api/moonsuite/engineering/audits',cookie,method='POST',payload=audit);check('MoonFish enrolled target resolves before control workspace check',status==400 and 'control workspace' in json.loads(body)['error'])
            result={'passed':len(checks),'checks':checks,'launcher':bool(a.launcher),'cwd':'non-repository temporary directory','upstream_services':'offline','binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'catalog_sha256':hashlib.sha256(original).hexdigest()};Path(a.output).write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result))
        finally:
            os.killpg(p.pid,signal.SIGTERM)
            try:p.wait(timeout=10)
            except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);p.wait()
            log.close()

if __name__=='__main__':main()
