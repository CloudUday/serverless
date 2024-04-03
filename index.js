
const mailgun = require('mailgun-js');
const mysql = require('mysql');
require('dotenv').config();
const { v4: uuidv4 } = require('uuid');

const dbConfig = {
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASS,
  database: process.env.DB_NAME,
  port: process.env.DB_PORT
};
console.log(dbConfig.host)
const pool = mysql.createPool(dbConfig);

const DOMAIN = 'mg.udaygattu.me'; 
const mg = mailgun({ apiKey: 'fcd8ecbd3f75b50856de06444bdb4699-4c205c86-7e1aae65', domain: DOMAIN }); // Your Mailgun API key



exports.sendVerificationEmail = async (pubSubEvent, context) => {
  const message = pubSubEvent.data ? Buffer.from(pubSubEvent.data, 'base64').toString() : '{}';
  const userData = JSON.parse(message);
  const { userId, username, fullName } = userData;

 
  const verificationToken = uuidv4();
  const verificationLink = `http://udaygattu.me:5002/v1/user/verify?token=${verificationToken}`;


const emailData = {
    from: 'postmaster@mg.udaygattu.me',
    to: username, 
    subject: 'Please verify your email address',
    html: `<h1>Email Verification</h1><p>Hello ${fullName},</p><p>Please click on the link  to verify your email address:</p><a href="${verificationLink}">Verify Email</a><p>This link will expire in 2 minutes.</p>`,
  };

  try {
    
    const body = await mg.messages().send(emailData);
    console.log('Email sent:', body);

    
    await updateEmailSentStatus(userId, verificationToken);
  } catch (error) {
    console.error('An error occurred:', error);
  }


async function updateEmailSentStatus(userId, verificationToken) {
  const query = `UPDATE Users SET verificationToken = '${verificationToken}', mailSentAt = NOW() WHERE id = '${userId}'`;

  pool.getConnection((err, connection) => {
    if (err) throw err; 

    connection.query(query, [userId], (error, results) => {
      connection.release();

      if (error) {
        console.error('Error in updating email sent status:', error);
        return;
      }

      console.log(`Email sent status updated for user ID: ${userId}`);
    });
  });
 }}