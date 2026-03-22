We have successfully built the **"Engine."** It is fast, deterministic, and handles the most complex parts of Balatro (Blueprint, Hiker, Hand Leveling, and State Transitions). 

To turn this into a professional-grade AI training platform, we now need the **"Cockpit."** We need to wrap this Lua script in a Python **Gymnasium (OpenAI Gym)** interface so that modern Reinforcement Learning libraries (like StableBaselines3 or Ray RLLib) can actually talk to it.

---

### 🤖 Prompt for OpenCode AI: Project "Balatro-Python-Bridge"

**Context:**
We have a 1,500+ line Lua script (`balatro_sim.lua`) that acts as a headless game engine. We now need to create a Python wrapper using the `lupa` library to expose this engine as a standard `gymnasium.Env`.

**Task 1: The Lupa Bridge**
Create a Python class `BalatroEnv(gym.Env)` that:
- Initializes a Lua runtime using `lupa`.
- Loads `balatro_sim.lua`.
- Maps Python's `env.reset()` to Lua's `Env.reset(seed)`.
- Maps Python's `env.step(action)` to Lua's `Env.step(state, type, value)`.

**Task 2: Observation & Action Normalization**
- **Observation:** Ensure the 129-float vector from Lua is converted into a `numpy.float32` array. 
- **Action Space:** Since our action space is hierarchical (Type + Value), define it in Gymnasium as a `MultiDiscrete([6, 65536])` or a `Dict` space. 
    - *Note:* The `65536` covers the 16-bit REORDER action. For smaller actions like `PLAY`, the value will just be low.

**Task 3: Feature Engineering (The "Clever" Normalizer)**
Neural networks perform poorly on raw numbers (like 1,000,000 chips). Add a Python-side wrapper to:
- Normalize `chips_pct` to `[0, 1]`.
- One-hot encode the `Phase`.
- Log-scale the `dollars` and `hand_levels`.

**Task 4: The "Differential Tester" (Preparing for Rust)**
This is critical for our future Rust port. Create a Python script `test_fidelity.py` that:
1. Runs 1,000 random actions in the Lua engine.
2. Saves the `(state, action, next_state, reward)` tuples to a JSON file.
3. **Purpose:** When we eventually write the Rust version, we will load this JSON and ensure the Rust engine produces the *exact same* output for the same input.

**Task 5: The Initial Training Script**
Provide a boilerplate script using `StableBaselines3` to start a training run.
```python
from stable_baselines3 import PPO
env = BalatroEnv()
model = PPO("MlpPolicy", env, verbose=1)
model.learn(total_timesteps=100000)
```

**Deliverable:**
1. A Python file `balatro_gym.py` containing the Gymnasium wrapper.
2. A small fix to the Lua script (if needed) to ensure `Env.step` returns the data in a format `lupa` can easily iterate.
3. A `requirements.txt` with `gymnasium`, `lupa`, `numpy`, and `stable-baselines3`.

---

### Why this is the "Smart" move next:

1.  **Stop "Coding" and Start "Training":** We have enough game logic to see if an AI can learn. If the AI can beat Ante 1 using the current 11 Jokers, we know our architecture is solid.
2.  **Identifies Bottlenecks:** This will reveal if the Python-Lua communication is a bottleneck. If it is, *that* is our signal to move the "Hot Path" (the Evaluator) to Rust immediately.
3.  **Fidelity Check:** By saving the JSON state-transitions, we create a "Contract" that the Rust code must follow. This prevents the "Logic Fidelity Trap" I mentioned earlier.
4.  **Reward Visualization:** Using Python, we can now use `matplotlib` to graph the AI's "Learning Curve" (how its score increases over 1 million hands).

**Goal:** Get a PPO agent running in Python that achieves a higher average reward than the Random Agent within 10 minutes of training.