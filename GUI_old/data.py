import json

with open('./TS_data_0.json') as json_file: data = json.load(json_file)

print(len(data['x_t']))