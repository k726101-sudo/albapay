const puppeteer = require('puppeteer');
(async () => {
  const browser = await puppeteer.launch({ headless: 'new' });
  const page = await browser.newPage();
  page.on('console', msg => console.log('PAGE LOG:', msg.text()));
  page.on('pageerror', error => console.log('PAGE ERROR:', error.message));
  page.on('requestfailed', request => console.log('REQ FAILED:', request.url(), request.failure().errorText));
  await page.goto('https://standard-albapay.web.app/', { waitUntil: 'networkidle2' });
  setTimeout(async () => {
    const title = await page.title();
    console.log('PAGE TITLE:', title);
    await browser.close();
  }, 2000);
})();
