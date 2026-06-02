import copy
import os
import uuid

class Component:
    _next_seq_id = 0

    def __init__(self, component_type, name, x=0, y=0, icon_path=None, properties=None):
        self.name = name
        self.type = component_type
        self.x = x
        self.y = y
        self.properties = properties or {}
        self.icon_path = icon_path

        self.uuid = str(uuid.uuid4())
        self.seq_id = Component._next_seq_id
        Component._next_seq_id += 1

        try:
            if self.type == "ONUTxDSP":
                self.icon_path = "icon/Tx_DSP.png"
            if self.type == "OLTTxDSP":
                self.icon_path = "icon/Tx_DSP.png"
            elif self.type == "DAC":
                self.icon_path = "icon/DAC.jpg"
            elif self.type == "Driver":
                self.icon_path = "icon/Driver.jpg"
            elif self.type == "LaserCW":
                self.icon_path = "icon/laser.png"
            elif self.type == "Modulator":
                self.icon_path = "icon/modulator.jpg"
            elif self.type == "OA":
                self.icon_path = "icon/OA.jpg"
            elif self.type == "LO":
                self.icon_path = "icon/laser.png"
            elif self.type == "Pol_Rot":
                self.icon_path = "icon/RotatePol.jpg"
            elif self.type == "Fiber":
                self.icon_path = "icon/fiber.jpg"
            elif self.type == "Splitter":
                self.icon_path = "icon/splitter.jpg"
            elif self.type == "ICR":
                self.icon_path = "icon/ICR.png"
            elif self.type == "TIA":
                self.icon_path = "icon/TIA.jpg"
            elif self.type == "ADC":
                self.icon_path = "icon/ADC.jpg"
            elif self.type == "OLTRxDSP":
                self.icon_path = "icon/Rx_DSP.png"
            elif self.type == "ONURxDSP":
                self.icon_path = "icon/Rx_DSP.png"
            elif self.type == "VOA":
                self.icon_path = "icon/VOA.jpg"
            elif self.type == "Scope":
                self.icon_path = "icon/Scope.jpg"
            elif self.type == "AWG":
                self.icon_path = "icon/AWG.png"
            elif self.type == "OPM":
                self.icon_path = "icon/OPM.jpg"
            elif self.type == "O-Analyzer":
                self.icon_path = "icon/Analyzer.png"
            elif self.type == "E-Analyzer":
                self.icon_path = "icon/Analyzer.png"
            elif self.type == "PowerMeter":
                self.icon_path = "icon/OPM.jpg"


            if self.icon_path:
                if os.path.exists(os.path.abspath(self.icon_path)):
                    # 直接使用图片存储路径，在图片存储文件夹位于项目根文件夹下时使用
                    self.icon_path = self.icon_path
                else:
                    # 获取当前文件所在路径，并拼接图片路径，仅当图片存储文件夹与脚本处于相同子文件夹下时使用
                    self.icon_path = os.path.join(os.path.dirname(__file__), self.icon_path)

        except Exception as basementIconException:
            print("Create basement or Design Widget Icon ErrorL: ", basementIconException)

        self.inputs = {}  # 输入连接列表
        self.outputs = {}  # 输出连接列表

    @property
    def id(self):
        return self.seq_id

    def to_dict(self):
        """转换为字典"""
        return {
            'uuid': self.uuid,
            'seq_id': self.seq_id,
            'name': self.name,
            'type': self.type,
            'x': self.x,
            'y': self.y,
            'icon_path': self.icon_path,
            'properties': copy.deepcopy(self.properties)
        }

    @classmethod
    def from_dict(cls, data):
        """从字典创建"""
        component = cls(data['type'], data['name'],
                        data['x'], data['y'], data['icon_path'],
                        data['properties'])
        component.uuid = data.get('uuid', str(uuid.uuid4()))
        component.seq_id = data.get('seq_id', component.seq_id)
        Component._next_seq_id = max(Component._next_seq_id, component.seq_id + 1)
        return component

    def add_input_connection(self, connection_id, input_port):
        """
        为组件添加输入连接，以 dict 形式存储，其中 key 为上游组件的 id，value 为本组件的连接端口。
        :param connection_id: 上游组件 id
        :param input_port: 本组件连接端口
        :return: None
        """
        if connection_id not in self.inputs:
            self.inputs[connection_id] = input_port

    def add_output_connection(self, connection_id, out_port):
        """
        为组件添加输出连接，以 dict 形式存储，其中 key 下游组件的 id，value 为本组件的连接端口。
        :param connection_id: 下游组件 id
        :param out_port: 本组件连接端口
        :return: None
        """
        if connection_id not in self.outputs:
            self.outputs[connection_id] = out_port

    def remove_connection(self, connection_id):
        """移除连接"""
        if connection_id in self.inputs:
            del self.inputs[connection_id]
        if connection_id in self.outputs:
            del self.outputs[connection_id]


class Connection:
    _next_seq_id = 0

    def __init__(self, source_id, target_id, source_port, target_port, properties=None):
        self.source_id = source_id
        self.target_id = target_id
        self.source_port = source_port
        self.target_port = target_port
        self.properties = properties or {}
        self.uuid = str(uuid.uuid4())
        self.seq_id = Connection._next_seq_id
        Connection._next_seq_id += 1

    @property
    def id(self):
        return self.seq_id

    def to_dict(self):
        """转换为字典"""
        return {
            'uuid': self.uuid,
            'seq_id': self.seq_id,
            'source_id': self.source_id,
            'target_id': self.target_id,
            'source_port': self.source_port,
            'target_port': self.target_port,
            'properties': copy.deepcopy(self.properties)
        }

    @classmethod
    def from_dict(cls, data):
        """从字典创建"""
        connection = cls(data['source_id'], data['target_id'], data['source_port'], data['target_port'],
                         data.get('properties', {}))
        connection.uuid = data.get('uuid', str(uuid.uuid4()))
        connection.seq_id = data.get('seq_id', connection.seq_id)
        connection._next_seq_id = max(connection._next_seq_id, connection.seq_id + 1)
        return connection

"""
class GlobalParameters:

    def __init__(self):
        self.parameters = {}
        self.default_parameters = {
        }

    def load_defaults(self):
        self.parameters = copy.deepcopy(self.default_parameters)

    def to_dict(self):
        return copy.deepcopy(self.parameters)

    def from_dict(self, data):
        self.parameters = copy.deepcopy(data)

    def get_value(self, key):
        if key in self.parameters:
            return self.parameters[key][0]
        return None

    def set_value(self, key, value, unit=""):
        if key in self.parameters:
            self.parameters[key][0] = value
        else:
            self.parameters[key] = [value, unit]

    def update_from_dict(self, data):
        for key, value in data.items():
            if isinstance(value, (list, tuple)) and len(value) >= 2:
                self.parameters[key] = [value[0], value[1]]
            else:
                self.parameters[key] = [value, ""]

"""
