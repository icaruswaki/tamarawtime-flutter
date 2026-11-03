'use strict';
// UI demonstration only. No data is sent to or saved in a database.
const DEMO_USER={id:'demo-user',email:'demo@tamarawtime.example'};
const demoDay=(new Date().getDay()+1)%7;
let demoPayload={
 classes:[
  {id:'demo-class-1',name:'Data Structures',day:demoDay,time:'09:00',end:'10:30',room:'Room 401',campus:'FEU Tech'},
  {id:'demo-class-2',name:'Introduction to AI',day:(demoDay+1)%7,time:'13:00',end:'14:30',room:'Lab 202',campus:'FEU Tech'}
 ],
 tasks:[],
 settings:{name:'Tamaraw',campus:'FEU Tech',travel:55,prep:45,buffer:15,mode:'Walking',theme:'forest'},
 onboarding:{finished:false}
};
let authListener=null;
const CloudStore={
 configured:true,db:{auth:{
  onAuthStateChange(fn){authListener=fn;return {data:{subscription:{unsubscribe(){}}}}},
  async getSession(){return {data:{session:{user:DEMO_USER}},error:null}},
  async signInWithPassword(){return {data:{user:DEMO_USER,session:{user:DEMO_USER}},error:null}},
  async signUp(){return {data:{user:DEMO_USER,session:{user:DEMO_USER}},error:null}},
  async signOut(){if(authListener)authListener('SIGNED_OUT',null);return {error:null}}
 }},
 setUser(){},getUser(){return DEMO_USER},
 async load(){return {payload:structuredClone(demoPayload)}},
 async savePayload(payload){demoPayload=structuredClone(payload)},
 async logEvent(){}
};
