import { sign } from 'jsonwebtoken';
import { JWT_SECRET_KEY } from '../constants';

const randomString = () => {
  return (
    Math.random()
      .toString(36)
      .substring(2, 15) +
    Math.random()
      .toString(36)
      .substring(2, 15)
  );
};

/**
 * Generates JWT with required fields
 * @param   {string} username
 * @returns {string} generated JWT
 */
export const getJwtToken = username => {
  // Populates claims with required fields
  const claims = { username };

  return sign(claims, JWT_SECRET_KEY, { expiresIn: '60m' });
};

/**
 * Calls external service which produces message to Kafka
 * @param   {object} data
 * @returns {promise}
 */
export const produceKafkaMessageAsync = (subscriberEvent, data) => {
  return fetch('/produce', {
    method: 'POST',
    body: JSON.stringify({
      cloudEventsVersion: '0.1',
      eventID: randomString(),
      eventType: subscriberEvent,
      source: 'events-example-ui',
      traceparent: "00-39fb839b1d9a53e8a5e0306526669021-8472fb1fee6307e5-01",
      tracestate: "example=channels,source=frontend",
      contentType: 'text/plain',
      data
    }),
    headers: { 'Content-Type': 'application/json' }
  }).then(response => response.json());
};
