// Local drafts are scoped to the signed-in user; the server is the archive authority.
function openDatabase() {
    return new Promise((resolve, reject) => {
        const req = indexedDB.open('umm-kulthum-drafts', 1);
        req.onupgradeneeded = () => req.result.createObjectStore('drafts');
        req.onsuccess = () => resolve(req.result);
        req.onerror = () => reject(new Error('تعذر حفظ المسودة على هذا الجهاز.'));
    });
}
async function operation(userId, mode, action) {
    const db = await openDatabase();
    try {
        return await new Promise((resolve, reject) => {
            const tx = db.transaction('drafts', mode), store = tx.objectStore('drafts');
            const request = action(store, userId);
            tx.oncomplete = () => resolve(request.result);
            tx.onabort = tx.onerror = () => reject(new Error('تعذر حفظ المسودة على هذا الجهاز.'));
        });
    } finally { db.close(); }
}
export const readDraft = userId => operation(userId, 'readonly', (store, key) => store.get(key));
export const writeDraft = (userId, draft) => operation(userId, 'readwrite', (store, key) => store.put(draft, key));
export const removeDraft = userId => operation(userId, 'readwrite', (store, key) => store.delete(key));
