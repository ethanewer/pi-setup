/**
 * Appointment request form built from a field definition list.
 */
function renderField(field) {
  if (field.type === 'textarea') {
    return <textarea id={field.name} rows="5" placeholder={field.hint} />;
  }
  if (field.type === 'select') {
    return (
      <select id={field.name}>
        <option value="">{field.placeholderOption}</option>
        {field.options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    );
  }
  return <input id={field.name} type={field.inputType || 'text'} placeholder={field.hint} />;
}

export default function BookingForm({ form }) {
  return (
    <section className="booking-form" aria-label="Booking form">
      <h4 className="form-title">{form.title}</h4>
      <p className="form-note">{form.note}</p>
      <form noValidate>
        {form.fields.map((field) => (
          <div key={field.name} className="field-row">{renderField(field)}</div>
        ))}
        <button type="submit" className="submit-button">{form.submitLabel}</button>
      </form>
    </section>
  );
}
