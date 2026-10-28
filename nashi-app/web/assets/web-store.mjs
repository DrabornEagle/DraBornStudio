let opening;
async function database() {
  return opening ||= new Promise((resolve, reject) => {
    const request = indexedDB.open('nashi-web-workspace-v1', 1);
    request.onupgradeneeded = () => { request.result.createObjectStore('inputs', { keyPath:'id' }); request.result.createObjectStore('exports', {keyPath:'id'}); };
    request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
  });
}
export async function records(store) { const db=await database(); return new Promise((resolve,reject)=>{const req=db.transaction(store).objectStore(store).getAll();req.onsuccess=()=>resolve(req.result);req.onerror=()=>reject(req.error);}); }
export async function persist(store, value) { const db=await database(); return new Promise((resolve,reject)=>{const tx=db.transaction(store,'readwrite');tx.objectStore(store).put(value);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);tx.onabort=()=>reject(tx.error);}); }
export async function remove(store, id) { const db=await database(); return new Promise((resolve,reject)=>{const tx=db.transaction(store,'readwrite');tx.objectStore(store).delete(id);tx.oncomplete=()=>resolve();tx.onerror=()=>reject(tx.error);}); }
