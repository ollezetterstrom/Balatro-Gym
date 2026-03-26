"""CI smoke test for balatro_gym full Gymnasium wrapper."""
import sys
import balatro_gym

env = balatro_gym.BalatroEnv()
obs, info = env.reset(seed=42)
assert obs.shape == (180,), f"Expected (180,), got {obs.shape}"
assert info["ante"] == 1

for i in range(30):
    action = env.action_space.sample()
    obs, r, d, t, info = env.step(action)
    assert obs.shape == (180,), f"Obs shape changed at step {i}: {obs.shape}"
    if d:
        break

env.close()
print(f"Full env: {i+1} steps, shape={obs.shape} - OK")
