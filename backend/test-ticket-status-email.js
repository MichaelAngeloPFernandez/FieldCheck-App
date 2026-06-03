/**
 * Test script for ticketStatusUpdateEmail template
 * Validates all requirements for Task 2
 */

const ticketStatusUpdateEmail = require('./utils/templates/ticketStatusUpdateEmail');

console.log('Testing Ticket Status Update Email Template\n');
console.log('='.repeat(50));

// Test data
const testCases = [
  {
    status: 'in_progress',
    expectedTitle: 'Work Has Started',
    expectedIcon: '🔧',
    expectedMessage: 'Our team has begun working on your support request.',
    shouldShowRating: false
  },
  {
    status: 'pending_review',
    expectedTitle: 'Under Review',
    expectedIcon: '👀',
    expectedMessage: 'Work has been completed and is now under review by our team.',
    shouldShowRating: false
  },
  {
    status: 'completed',
    expectedTitle: 'Work Completed',
    expectedIcon: '✅',
    expectedMessage: 'Your support request has been completed successfully!',
    shouldShowRating: true
  },
  {
    status: 'closed',
    expectedTitle: 'Ticket Closed',
    expectedIcon: '🔒',
    expectedMessage: 'Your support ticket has been closed.',
    shouldShowRating: false
  }
];

const clientName = 'John Doe';
const ticketNumber = 'RNG-20250115-A1B2';
const trackingLink = 'https://example.com/client-ticket/RNG-20250115-A1B2?token=abc123xyz';

let allTestsPassed = true;

testCases.forEach((testCase, index) => {
  console.log(`\nTest ${index + 1}: ${testCase.status}`);
  console.log('-'.repeat(50));
  
  const html = ticketStatusUpdateEmail(clientName, ticketNumber, testCase.status, trackingLink);
  
  // Requirement 6.1: Email SHALL include the ticket number in the subject line
  // (Subject line is set by emailService, but ticket number must be in body)
  const hasTicketNumber = html.includes(ticketNumber);
  console.log(`✓ Contains ticket number: ${hasTicketNumber ? 'PASS' : 'FAIL'}`);
  if (!hasTicketNumber) allTestsPassed = false;
  
  // Requirement 6.2: Email SHALL include the new status value in human-readable format
  const hasStatusMessage = html.includes(testCase.expectedTitle) && html.includes(testCase.expectedMessage);
  console.log(`✓ Contains status message: ${hasStatusMessage ? 'PASS' : 'FAIL'}`);
  if (!hasStatusMessage) allTestsPassed = false;
  
  // Requirement 6.3: Email SHALL include a direct link to the ticket tracking page
  const hasTrackingLink = html.includes(trackingLink) && html.includes('View Ticket Details');
  console.log(`✓ Contains tracking link: ${hasTrackingLink ? 'PASS' : 'FAIL'}`);
  if (!hasTrackingLink) allTestsPassed = false;
  
  // Requirement 6.4: Email SHALL include instructions for submitting a rating (for completed status)
  const hasRatingPrompt = html.includes('Rate Your Experience');
  const ratingPromptCorrect = testCase.shouldShowRating ? hasRatingPrompt : !hasRatingPrompt;
  console.log(`✓ Rating prompt ${testCase.shouldShowRating ? 'present' : 'absent'}: ${ratingPromptCorrect ? 'PASS' : 'FAIL'}`);
  if (!ratingPromptCorrect) allTestsPassed = false;
  
  // Additional checks
  const hasClientName = html.includes(clientName);
  console.log(`✓ Contains client name: ${hasClientName ? 'PASS' : 'FAIL'}`);
  if (!hasClientName) allTestsPassed = false;
  
  const hasIcon = html.includes(testCase.expectedIcon);
  console.log(`✓ Contains status icon: ${hasIcon ? 'PASS' : 'FAIL'}`);
  if (!hasIcon) allTestsPassed = false;
  
  const hasGradientHeader = html.includes('linear-gradient(135deg, #667eea 0%, #764ba2 100%)');
  console.log(`✓ Has gradient header: ${hasGradientHeader ? 'PASS' : 'FAIL'}`);
  if (!hasGradientHeader) allTestsPassed = false;
  
  const hasTicketBox = html.includes('ticket-box') && html.includes('Ticket Number');
  console.log(`✓ Has ticket number display box: ${hasTicketBox ? 'PASS' : 'FAIL'}`);
  if (!hasTicketBox) allTestsPassed = false;
  
  const hasViewButton = html.includes('button') && html.includes('View Ticket Details');
  console.log(`✓ Has "View Ticket Details" button: ${hasViewButton ? 'PASS' : 'FAIL'}`);
  if (!hasViewButton) allTestsPassed = false;
  
  const hasFooter = html.includes('This is an automated notification from FieldCheck');
  console.log(`✓ Has automated notification footer: ${hasFooter ? 'PASS' : 'FAIL'}`);
  if (!hasFooter) allTestsPassed = false;
  
  const isResponsive = html.includes('max-width: 600px') && html.includes('viewport');
  console.log(`✓ Is responsive (mobile-friendly): ${isResponsive ? 'PASS' : 'FAIL'}`);
  if (!isResponsive) allTestsPassed = false;
});

console.log('\n' + '='.repeat(50));
console.log(`\nFinal Result: ${allTestsPassed ? '✅ ALL TESTS PASSED' : '❌ SOME TESTS FAILED'}`);
console.log('\nRequirements Validated:');
console.log('  ✓ 6.1: Ticket number included in email');
console.log('  ✓ 6.2: Status in human-readable format');
console.log('  ✓ 6.3: Direct link to tracking page');
console.log('  ✓ 6.4: Rating instructions for completed status');

process.exit(allTestsPassed ? 0 : 1);
