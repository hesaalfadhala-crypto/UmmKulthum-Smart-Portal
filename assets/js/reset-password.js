import {client} from './portal-data.js';
const form=document.getElementById('resetForm'),status=document.getElementById('status'),button=document.getElementById('savePassword');let recovery=false,busy=false;
// An existing normal login is insufficient; only a valid recovery link exposes the form.
client.auth.onAuthStateChange((event)=>{if(event==='PASSWORD_RECOVERY'){recovery=true;form.hidden=false;status.textContent='أدخلي كلمة مرور جديدة ثم أكديها.';}});
form.addEventListener('submit',async(event)=>{
 event.preventDefault();if(!recovery||busy)return;
 const password=document.getElementById('newPassword').value,confirmation=document.getElementById('confirmPassword').value;
 if(password!==confirmation){status.textContent='كلمتا المرور غير متطابقتين.';return;}
 if(password.length<8){status.textContent='يجب أن تتكون كلمة المرور من 8 أحرف على الأقل.';return;}
 busy=true;button.disabled=true;
 try{const {error}=await client.auth.updateUser({password});if(error)throw error;
  form.reset();form.hidden=true;recovery=false;
  const {error:logoutError}=await client.auth.signOut({scope:'local'});
  status.textContent=logoutError?'تم تغيير كلمة المرور. أعيدي تسجيل الدخول.':'تم تغيير كلمة المرور. يمكنكِ تسجيل الدخول بالكلمة الجديدة.';
 }catch{status.textContent='تعذر تغيير كلمة المرور. افتحي أحدث رابط استعادة أو حاولي لاحقًا.';}
 finally{busy=false;button.disabled=false;}
});
