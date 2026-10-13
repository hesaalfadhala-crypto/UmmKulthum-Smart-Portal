import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
import nodemailer from 'npm:nodemailer@7.0.10';
import {createAccountEmailHandler} from '../_shared/account-email-handler.js';
Deno.serve(createAccountEmailHandler({createClient,nodemailer,env:(name:string)=>Deno.env.get(name)}));
