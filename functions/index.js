const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// Set global options for V2 functions only
setGlobalOptions({maxInstances: 10});

// 1. Your 'helloWorld' function (V2 syntax)
exports.helloWorld = onRequest((request, response) => {
  logger.info("Hello logs!", {structured: true});
  response.send("Hello from Firebase!");
});

exports.myFunctionName = onRequest((request, response) => {
  logger.info("Function executed successfully!", {structured: true});
  response.send("Hello from Firebase!");
});
