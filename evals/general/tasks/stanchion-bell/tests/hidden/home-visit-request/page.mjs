export default {
  slug: 'request-visit',
  announcement: 'Phone lines are busiest between 08:00 and 10:00; web requests are answered first.',
  title: 'Request a home visit',
  intro:
    'Fill in the form and a care coordinator will call you back within one ' +
    'business day to confirm the visit window and the caregiver assigned.',
  cta: { label: 'After-hours advice line', href: 'tel:+1-555-0164' },
  site: {
    name: 'Lanternwell Clinic',
    nav: [
      { label: 'Home', href: '#home' },
      { label: 'Services', href: '#services' },
      { label: 'Book an appointment', href: '#book' },
      { label: 'Contact', href: '#contact' },
    ],
  },
  cards: [],
  sidebarLinks: [
    { label: 'Emergency line', href: 'tel:+1-555-0100' },
    { label: 'After-hours advice', href: '#advice' },
  ],
  form: {
    title: 'Home visit request',
    submitLabel: 'Request a visit',
    note: 'We cannot guarantee same-day visits; urgent cases should call the emergency line.',
    fields: [
      { type: 'text', name: 'full-name', label: 'Full name', hint: 'Jane Doe' },
      { type: 'text', name: 'contact-phone', label: 'Phone number', hint: '(555) 010-1234', inputType: 'tel' },
      { type: 'select', name: 'care-type', label: 'Type of care', placeholderOption: 'Choose a type of care',
        options: [
          { value: 'wound', label: 'Wound care' },
          { value: 'medicine', label: 'Medication review' },
          { value: 'assessment', label: 'General assessment' },
        ] },
      { type: 'textarea', name: 'details', label: 'What we should know', hint: 'Mobility, stairs, notes for the caregiver' },
    ],
  },
};