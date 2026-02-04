import '../styles/Skeleton.css';

export const Skeleton = ({ type = 'card' }) => {
  if (type === 'card') {
    return (
      <div className="skeleton-card">
        <div className="skeleton-image"></div>
        <div className="skeleton-content">
          <div className="skeleton-line"></div>
          <div className="skeleton-line short"></div>
          <div className="skeleton-line"></div>
        </div>
      </div>
    );
  }

  if (type === 'hero') {
    return <div className="skeleton-hero"></div>;
  }

  return <div className="skeleton-block"></div>;
};
