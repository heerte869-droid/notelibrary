#!/usr/bin/env python3
"""Offline app-server fixture. Never reads accounts or sends network requests."""
import json,sys,threading,time,pathlib
lock=threading.Lock(); counter=0; turns={}
def send(x):
 with lock:
  print(json.dumps(x),flush=True)
def notification(method,params): send({'method':method,'params':params})
def finish(thread,turn,prompt,delay,schema):
 notification('turn/started',{'threadId':thread,'turn':{'id':turn,'status':'inProgress'}})
 if prompt=='reconnect':
  notification('error',{'threadId':thread,'turnId':turn,'willRetry':True,'error':{'message':'Reconnecting... 1/5','codexErrorInfo':{'responseStreamDisconnected':{'httpStatusCode':None}}}})
 notification('item/reasoning/summaryTextDelta',{'threadId':thread,'turnId':turn,'delta':'PRIVATE_REASONING_MUST_NOT_BE_DISPLAYED'})
 time.sleep(delay)
 if turns.get(turn):
  notification('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'completed'}})
  return
 if prompt=='fail':
  notification('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'failed','error':{'message':'fixture failure'}}})
  return
 text=json.dumps({'action':'reply','message':'测试回复已返回。','questions':[],'notes':[],'references':[],'searchQueries':[]},ensure_ascii=False)
 if pathlib.Path('final-plan.json').exists():
  text=pathlib.Path('final-plan.json').read_text()
  for n in range(3):
   notification('item/completed',{'threadId':thread,'turnId':turn,'item':{'type':'imageView','id':turn+'-image-'+str(n),'status':'completed'}})
 if '以下草稿未通过成品检查' in prompt and pathlib.Path('editorial-plan.json').exists():
  text=pathlib.Path('editorial-plan.json').read_text()
 if 'pages' in schema.get('properties',{}):
  ids=schema['properties']['pages']['items']['properties']['sourceID']['enum']
  pages=[{'sourceID':sid,'transcript':'原稿 '+sid+' 完整内容【待核对】'} for sid in reversed(ids)]
  if pathlib.Path('incomplete-reading').exists(): pages=pages[:-1]
  text=json.dumps({'pages':pages},ensure_ascii=False)
 notification('item/agentMessage/delta',{'threadId':thread,'turnId':turn,'itemId':turn+'-message','delta':text})
 notification('item/completed',{'threadId':thread,'turnId':turn,'item':{'type':'agentMessage','text':text,'phase':'final_answer'}})
 notification('turn/completed',{'threadId':thread,'turn':{'id':turn,'status':'completed'}})
for line in sys.stdin:
 try: obj=json.loads(line)
 except: continue
 with open('rpc.jsonl','a') as f: f.write(json.dumps(dict(obj,fixtureTime=time.monotonic()))+'\n')
 if 'id' not in obj: continue
 method=obj['method']; params=obj.get('params',{}); result={}
 if method=='account/read': result={'account':{'type':'fixture'}}
 elif method=='model/list': result={'data':json.loads(pathlib.Path('models.json').read_text()) if pathlib.Path('models.json').exists() else [{'model':'gpt-6.1-sol','displayName':'GPT-6.1 Sol','supportedReasoningEfforts':[{'reasoningEffort':'medium'}],'isDefault':True}]}
 elif method=='skills/list': result={'data':[]}
 elif method=='thread/start':
  counter+=1;result={'thread':{'id':'thread-'+str(counter)}}
 elif method=='turn/start':
  counter+=1;turn='turn-'+str(counter);thread=params['threadId'];turns[turn]=False
  prompt=next((i['text'] for i in reversed(params.get('input',[])) if i.get('type')=='text'),'')
  send({'id':obj['id'],'result':{'turn':{'id':turn,'status':'inProgress'}}})
  delay=float(pathlib.Path('delay-seconds').read_text()) if pathlib.Path('delay-seconds').exists() else (0.5 if prompt=='slow' else 0.02)
  schema=params.get('outputSchema',{})
  if 'pages' in schema.get('properties',{}) and pathlib.Path('batch-delays.json').exists():
   ids=schema['properties']['pages']['items']['properties']['sourceID']['enum']
   delay=max(json.loads(pathlib.Path('batch-delays.json').read_text()).get(sid,0.02) for sid in ids)
  threading.Thread(target=finish,args=(thread,turn,prompt,delay,schema),daemon=True).start();continue
 elif method=='turn/interrupt':
  turns[params['turnId']]=True
  notification('turn/completed',{'threadId':params['threadId'],'turn':{'id':params['turnId'],'status':'interrupted'}})
 send({'id':obj['id'],'result':result})
