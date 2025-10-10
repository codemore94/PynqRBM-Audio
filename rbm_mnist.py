import numpy as np
import tensorflow as tf
from tensorflow.keras.datasets import mnist
import matplotlib.pyplot as plt

class RBM:
    def __init__(self, n_visible, n_hidden, learning_rate=0.1):
        self.n_visible = n_visible
        self.n_hidden = n_hidden
        self.learning_rate = learning_rate
        
        # Weights and biases initialization
        self.W = tf.random.normal((n_visible, n_hidden), mean=0, stddev=0.01, dtype=tf.float32)
        self.b_h = tf.zeros((n_hidden,), dtype=tf.float32)
        self.b_v = tf.zeros((n_visible,), dtype=tf.float32)
        
    def sample_h(self, v):
        h_prob = tf.sigmoid(tf.matmul(v, self.W) + self.b_h)  # P(h=1|v)
        h_sample = tf.cast(tf.random.uniform(h_prob.shape) < h_prob, tf.float32)  # Sample h
        return h_sample, h_prob
    
    def sample_v(self, h):
        v_prob = tf.sigmoid(tf.matmul(h, tf.transpose(self.W)) + self.b_v)  # P(v=1|h)
        v_sample = tf.cast(tf.random.uniform(v_prob.shape) < v_prob, tf.float32)  # Sample v
        return v_sample, v_prob
    
    def fit(self, data, epochs=10, batch_size=100):
        num_samples = data.shape[0]
        
        for epoch in range(epochs):
            np.random.shuffle(data)  # Shuffle the data
            
            for i in range(0, num_samples, batch_size):
                batch = data[i:i + batch_size]
                
                # Convert batch to tf.float32
                batch = tf.convert_to_tensor(batch, dtype=tf.float32)

                # Positive phase
                h_sample, h_prob = self.sample_h(batch)
                positive_grad = tf.matmul(tf.transpose(batch), h_prob) / batch_size
                
                # Negative phase
                v_sample, _ = self.sample_v(h_sample)
                h_sample_neg, _ = self.sample_h(v_sample)
                negative_grad = tf.matmul(tf.transpose(v_sample), h_sample_neg) / batch_size
                
                # Update weights and biases
                self.W += self.learning_rate * (positive_grad - negative_grad)
                self.b_v += self.learning_rate * tf.reduce_mean(batch - v_sample, axis=0)
                self.b_h += self.learning_rate * tf.reduce_mean(h_prob - h_sample_neg, axis=0)

            print(f"Epoch {epoch + 1}/{epochs} complete.")

    def transform(self, data):
        data = tf.convert_to_tensor(data, dtype=tf.float32)  # Ensure data is float32
        h_prob = tf.sigmoid(tf.matmul(data, self.W) + self.b_h)
        return h_prob

# Load MNIST dataset
(x_train, y_train), (x_test, y_test) = mnist.load_data()
x_train = x_train.reshape(-1, 28 * 28) / 255.0  # Flatten and normalize
x_test = x_test.reshape(-1, 28 * 28) / 255.0

# Create and train the RBM
n_visible = 28 * 28  # Input layer size (784 for MNIST)
n_hidden = 256       # Size of hidden layer
rbm = RBM(n_visible, n_hidden, learning_rate=0.1)

# Train the RBM
rbm.fit(x_train, epochs=10, batch_size=100)

# Transform the test data
hidden_representation = rbm.transform(x_test)

# Visualize the weights of the RBM
def plot_weights(weights, n_cols=8):
    n_weights = weights.shape[1]
    n_rows = n_weights // n_cols
    plt.figure(figsize=(n_cols, n_rows))
    for i in range(n_weights):
        plt.subplot(n_rows, n_cols, i + 1)
        plt.imshow(weights[:, i].numpy().reshape(28, 28), cmap='gray')
        plt.axis('off')
    #plt.show()
    plt.savefig("kuva.png")
# Plot the learned weights
plot_weights(rbm.W)
