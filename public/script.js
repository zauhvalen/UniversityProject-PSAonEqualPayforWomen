const currentPage = document.body.dataset.page;
const navLinks = Array.from(document.querySelectorAll("[data-nav]"));

navLinks.forEach((link) => {
  if (link.dataset.nav === currentPage) {
    link.setAttribute("aria-current", "page");
  }
});

// Fade-up animation using Intersection Observer
const observerOptions = {
  root: null,
  rootMargin: '0px',
  threshold: 0.1
};

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('visible');
      observer.unobserve(entry.target);
    }
  });
}, observerOptions);

const fadeElements = document.querySelectorAll('.fade-up');

// Check elements already in viewport on page load
const checkInitialVisibility = () => {
  fadeElements.forEach((el) => {
    const rect = el.getBoundingClientRect();
    if (rect.top < window.innerHeight && rect.bottom > 0) {
      el.classList.add('visible');
    } else {
      observer.observe(el);
    }
  });
};

// Run on load and after a small delay to ensure DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', checkInitialVisibility);
} else {
  checkInitialVisibility();
}