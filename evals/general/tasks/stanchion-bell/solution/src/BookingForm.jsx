/**
 * Appointment request form built from a field definition list. Every control
 * carries an explicit label associated through the label element.
 */
function renderField(field) {
  if (field.type === 'textarea') {
    return (
      <label className="field-label" htmlFor={field.name}>
        {field.label}
        <textarea id={field.name} name={field.name} rows="5" placeholder={field.hint} />
      </label>
    );
  }
  if (field.type === 'select') {
    return (
      <label className="field-label" htmlFor={field.name}>
        {field.label}
        <select id={field.name} name={field.name}>
          <option value="">{field.placeholderOption}</option>
          {field.options.map((o) => (
            <option key={o.value} value={o.value}>{o.label}</option>
          ))}
        </select>
      </label>
    );
  }
  return (
    <label className="field-label" htmlFor={field.name}>
      {field.label}
      <input id={field.name} name={field.name} type={field.inputType || 'text'} placeholder={field.hint} />
    </label>
  );
}

export default function BookingForm({ form }) {
  return (
    <section className="booking-form" aria-label="Booking form">
      <h2 className="form-title">{form.title}</h2>
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
