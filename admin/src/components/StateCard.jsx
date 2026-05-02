import PropTypes from "prop-types";
import "../styles/StateCard.css";

function StateCard({
  icon,
  title,
  description,
  actionLabel,
  onAction,
  variant = "empty",
}) {
  return (
    <section className={`state-card state-card--${variant}`} role="status" aria-live="polite">
      <div className="state-card__icon" aria-hidden="true">{icon}</div>
      <h3 className="state-card__title">{title}</h3>
      <p className="state-card__description">{description}</p>
      {actionLabel && onAction && (
        <button className="state-card__action" type="button" onClick={onAction}>
          {actionLabel}
        </button>
      )}
    </section>
  );
}

StateCard.propTypes = {
  icon: PropTypes.string,
  title: PropTypes.string.isRequired,
  description: PropTypes.string,
  actionLabel: PropTypes.string,
  onAction: PropTypes.func,
  variant: PropTypes.oneOf(["empty", "loading"]),
};

StateCard.defaultProps = {
  icon: "✨",
  description: "",
  actionLabel: "",
  onAction: null,
  variant: "empty",
};

export default StateCard;
