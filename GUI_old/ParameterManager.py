import copy
import json
from enum import Enum
from typing import Dict, Any, List, Union, Optional
import numpy as np


# ==================== 参数类型与验证器 ====================
class ParameterType(Enum):
    """参数类型枚举"""
    FLOAT = "float"
    INTEGER = "int"
    STRING = "string"
    BOOL = "bool"
    ARRAY = "array"
    COMPLEX = "complex"
    FREQUENCY = "frequency"
    POWER = "power"
    LENGTH = "length"
    TIME = "time"


class ParameterValidator:
    """参数验证器"""

    @staticmethod
    def validate_frequency(value: Any) -> bool:
        try:
            val = float(value)
            return val >= 0
        except (ValueError, TypeError):
            return False

    @staticmethod
    def validate_power(value: Any) -> bool:
        try:
            float(value)
            return True
        except (ValueError, TypeError):
            return False

    @staticmethod
    def validate_positive(value: Any) -> bool:
        try:
            val = float(value)
            return val > 0
        except (ValueError, TypeError):
            return False

    @staticmethod
    def validate_nonnegative(value: Any) -> bool:
        try:
            val = float(value)
            return val >= 0
        except (ValueError, TypeError):
            return False

    @staticmethod
    def validate_integer(value: Any) -> bool:
        try:
            int(value)
            return True
        except (ValueError, TypeError):
            return False

    @staticmethod
    def validate_array(value: Any) -> bool:
        return isinstance(value, (list, tuple, np.ndarray))

    @staticmethod
    def get_validator(param_type: ParameterType):
        validators = {
            ParameterType.FREQUENCY: ParameterValidator.validate_frequency,
            ParameterType.POWER: ParameterValidator.validate_power,
            ParameterType.LENGTH: ParameterValidator.validate_positive,
            ParameterType.TIME: ParameterValidator.validate_positive,
            ParameterType.FLOAT: lambda x: isinstance(x, (int, float, np.number)),
            ParameterType.INTEGER: ParameterValidator.validate_integer,
            ParameterType.ARRAY: ParameterValidator.validate_array,
        }
        return validators.get(param_type, lambda x: True)


# ==================== 参数类 ====================
class Parameter:
    """单个参数定义"""

    def __init__(self, name: str, value: Any, unit: str = "",
                 description: str = "", param_type: ParameterType = None,
                 min_value: Optional[float] = None, max_value: Optional[float] = None,
                 options: Optional[List] = None):
        self.name = name
        self.value = value
        self.unit = unit
        self.description = description
        self.type = param_type or self._guess_type(value)
        self.min_value = min_value
        self.max_value = max_value
        self.options = options
        self.validate()

    def _guess_type(self, value):
        if isinstance(value, (int, np.integer)):
            return ParameterType.INTEGER
        elif isinstance(value, (float, np.floating)):
            return ParameterType.FLOAT
        elif isinstance(value, bool):
            return ParameterType.BOOL
        elif isinstance(value, str):
            return ParameterType.STRING
        elif isinstance(value, (list, tuple, np.ndarray)):
            return ParameterType.ARRAY
        elif isinstance(value, complex):
            return ParameterType.COMPLEX
        else:
            return ParameterType.STRING

    def validate(self):
        validator = ParameterValidator.get_validator(self.type)
        if not validator(self.value):
            raise ValueError(f"Invalid value {self.value} for parameter {self.name} of type {self.type}")

        if self.min_value is not None:
            try:
                if float(self.value) < self.min_value:
                    raise ValueError(f"Value {self.value} is below minimum {self.min_value}")
            except (ValueError, TypeError):
                pass

        if self.max_value is not None:
            try:
                if float(self.value) > self.max_value:
                    raise ValueError(f"Value {self.value} is above maximum {self.max_value}")
            except (ValueError, TypeError):
                pass

        if self.options and self.value not in self.options:
            raise ValueError(f"Value {self.value} is not in allowed options {self.options}")

    def to_dict(self) -> Dict:
        result = {
            "name": self.name,
            "value": self.value,
            "unit": self.unit,
            "description": self.description,
            "type": self.type.value
        }
        if self.min_value is not None:
            result["min_value"] = self.min_value
        if self.max_value is not None:
            result["max_value"] = self.max_value
        if self.options is not None:
            result["options"] = self.options
        return result

    @classmethod
    def from_dict(cls, data: Dict):
        param_type = ParameterType(data.get("type", "string"))
        return cls(
            name=data["name"],
            value=data["value"],
            unit=data.get("unit", ""),
            description=data.get("description", ""),
            param_type=param_type,
            min_value=data.get("min_value"),
            max_value=data.get("max_value"),
            options=data.get("options")
        )

    def __repr__(self):
        return f"Parameter({self.name}={self.value} {self.unit})"


# ==================== 参数集合 ====================
class ParameterSet:
    """一组参数的集合"""

    def __init__(self, name: str = ""):
        self.name = name
        self.parameters: Dict[str, Parameter] = {}

    def add_parameter(self, param: Parameter):
        self.parameters[param.name] = param

    def get_parameter(self, name: str, default=None) -> Optional[Parameter]:
        return self.parameters.get(name, default)

    def get_value(self, name: str, default=None):
        param = self.get_parameter(name)
        return param.value if param else default

    def set_parameter(self, name: str, value: Any, unit: str = "",
                      description: str = "", param_type: ParameterType = None,
                      min_value: Optional[float] = None, max_value: Optional[float] = None,
                      options: Optional[List] = None):
        if name in self.parameters:
            param = self.parameters[name]
            param.value = value
            if unit:
                param.unit = unit
            if description:
                param.description = description
            if param_type:
                param.type = param_type
            param.min_value = min_value
            param.max_value = max_value
            param.options = options
            param.validate()
        else:
            param = Parameter(name, value, unit, description, param_type,
                              min_value, max_value, options)
            self.parameters[name] = param

    def remove_parameter(self, name: str):
        if name in self.parameters:
            del self.parameters[name]

    def to_dict(self) -> Dict:
        return {
            "name": self.name,
            "parameters": {name: param.to_dict() for name, param in self.parameters.items()}
        }

    @classmethod
    def from_dict(cls, data: Dict):
        param_set = cls(data.get("type", ""))
        for param_data in data.get("parameters", {}).values():
            param_set.add_parameter(Parameter.from_dict(param_data))
        return param_set

    def merge(self, other: 'ParameterSet', overwrite=True):
        for name, param in other.parameters.items():
            if overwrite or name not in self.parameters:
                self.parameters[name] = param

    def __repr__(self):
        return f"ParameterSet({self.name}, {len(self.parameters)} parameters)"


# ==================== 统一参数管理器 ====================
class ParameterManager:
    """
    统一参数管理器：集成全局参数与组件参数模板。

    功能：
    - 全局参数管理（类似原来的 GlobalParameters）
    - 组件参数模板管理（类似原来的 ComponentParameterManager）
    - 参数验证、合并、保存/加载
    """

    def __init__(self):
        # 全局参数集（作为特殊的 ParameterSet）
        self._global_params = ParameterSet("Global")
        # 组件参数模板字典
        self.component_templates: Dict[str, ParameterSet] = self._create_default_templates()

        print(self.component_templates)
        # 将全局参数模板指向 _global_params
        self.component_templates["Global"] = self._global_params

        # 加载默认的全局参数
        self.load_defaults()

    def _create_default_templates(self) -> Dict[str, ParameterSet]:
        """创建默认组件参数模板（不含 Global，Global 单独处理）"""
        templates = {}

        # TxDSP (适用于下行 OLT 和上行 ONU，具体值在链路中可覆盖)
        onu_tx_dsp = ParameterSet("ONUTxDSP")
        # onu_tx_dsp.set_parameter("Fs_Tx", 92e9, "Hz", "Transmitter Sampling Rate", ParameterType.FREQUENCY)
        onu_tx_dsp.set_parameter("BaudRate", 25e9, "Baud", "Symbol Rate", ParameterType.FLOAT)
        onu_tx_dsp.set_parameter("M", 16, "", "Modulation Order", ParameterType.INTEGER)
        onu_tx_dsp.set_parameter("num_bands", 4, "", "Number of SCM subcarriers (downlink)", ParameterType.INTEGER)
        # onu_tx_dsp.set_parameter("span", 128, "", "RRC filter span (symbols)", ParameterType.INTEGER)
        # onu_tx_dsp.set_parameter("rolloff", 0.1, "", "Roll-off factor", ParameterType.FLOAT)
        # onu_tx_dsp.set_parameter("grdbw", 2e9, "Hz", "Guard bandwidth (downlink)", ParameterType.FREQUENCY)
        # onu_tx_dsp.set_parameter("SPPR", 20, "dB", "Signal-to-Pilot Power Ratio (downlink)", ParameterType.FLOAT)
        onu_tx_dsp.set_parameter("symbolnum", 32768, "", "Number of symbols per ONU", ParameterType.INTEGER)
        # onu_tx_dsp.set_parameter("RandSeed", 1000, "", "Random seed base", ParameterType.INTEGER)
        templates["ONUTxDSP"] = onu_tx_dsp

        olt_tx_dsp = ParameterSet("OLTTxDSP")
        olt_tx_dsp.set_parameter("BaudRate", 6.25e9, "Baud", "Symbol Rate", ParameterType.FLOAT)
        olt_tx_dsp.set_parameter("M", 16, "", "Modulation Order", ParameterType.INTEGER)
        olt_tx_dsp.set_parameter("num_bands", 4, "", "Number of SCM subcarriers (downlink)", ParameterType.INTEGER)
        olt_tx_dsp.set_parameter("symbolnum", 32768, "", "Number of symbols per ONU", ParameterType.INTEGER)
        templates["OLTTxDSP"] = olt_tx_dsp

        # DAC (基于 Keysight M8196A)
        dac = ParameterSet("DAC")
        dac.set_parameter("sampling_rate", 92e9, "Sa/s", "Sampling Rate", ParameterType.FREQUENCY)
        dac.set_parameter("DAC_BW_Analog", 32e9, "Hz", "DAC analog bandwidth", ParameterType.FREQUENCY)
        dac.set_parameter("Resolution", 8, "", "Effective number of bits", ParameterType.INTEGER)
        templates["DAC"] = dac

        # Driver (Electrical amplifier)
        driver = ParameterSet("Driver")
        driver.set_parameter("Bandwidth", 35e9, "Hz", "Driver bandwidth (-3dB)", ParameterType.FREQUENCY)
        driver.set_parameter("Gain_dB", 3, "dB", "Linear gain", ParameterType.FLOAT)
        templates["Driver"] = driver

        # Modulator (IQ Mach-Zehnder)
        modulator = ParameterSet("Modulator")
        modulator.set_parameter("Vpi", 3.0, "V", "Half-wave voltage (RF)", ParameterType.FLOAT, min_value=0.1)
        modulator.set_parameter("VpiDC", 3.0, "V", "Half-wave voltage (DC bias)", ParameterType.FLOAT, min_value=0.1)
        modulator.set_parameter("Bandwidth", 35e9, "Hz", "Modulator Bandwidth", ParameterType.FREQUENCY)
        # modulator.set_parameter("ExtinctionRatio", 50, "dB", "Child MZ extinction ratio", ParameterType.FLOAT)
        # modulator.set_parameter("PushPull", True, "", "Push-pull configuration", ParameterType.BOOL)
        templates["Modulator"] = modulator

        # Optical Amplifier (EDFA, power-controlled mode)
        amp = ParameterSet("OA")
        amp.set_parameter("OutputPower", 1e-3, "W", "Target output power", ParameterType.POWER)
        amp.set_parameter("GainMax", 100, "dB", "Maximum gain", ParameterType.FLOAT)
        amp.set_parameter("NoiseFigure", 5.0, "dB", "Noise figure", ParameterType.FLOAT)
        amp.set_parameter("Type", "PowerControlled", "", "Operating mode", ParameterType.STRING)
        amp.set_parameter("Scan_Tx_Power_MinVal", 0, "dBm", "Scan Min Power Value", ParameterType.POWER)
        amp.set_parameter("Scan_Tx_Power_MaxVal", 0, "dBm", "Scan Max Power Value", ParameterType.POWER)
        templates["OA"] = amp


        laser = ParameterSet("LaserCW")
        laser.set_parameter("EmissionFrequency", 193.1e12, "Hz", "Emission frequency", ParameterType.FREQUENCY)
        laser.set_parameter("AveragePower", 20e-3, "W", "Average power", ParameterType.FLOAT)
        # laser.set_parameter("SideModeSeparation", 200e9, "Hz", "Side mode separation", ParameterType.FREQUENCY)
        # laser.set_parameter("SideModeSuppressionRatio", 100, "dB", "Side mode suppression ratio", ParameterType.FLOAT)
        laser.set_parameter("Linewidth", 100e3, "Hz", "Line width", ParameterType.FREQUENCY)
        # laser.set_parameter("Azimuth", 45, "deg", "Azimuth angle", ParameterType.FLOAT)
        # laser.set_parameter("Ellipticity", 0, "deg", "Ellipticity angle", ParameterType.FLOAT)
        # laser.set_parameter("EmissionFrequencyDrift", 1.0e9, "", "Emission frequency drift", ParameterType.FLOAT)
        # laser.set_parameter("CaseTemperature", 25, "C", "Case temperature", ParameterType.FLOAT)
        # laser.set_parameter("ReferenceTemperature", 25, "C", "Reference temperature", ParameterType.FLOAT)
        laser.set_parameter("RIN", -150, "dB/Hz", "RIN", ParameterType.FLOAT)
        # laser.set_parameter("RIN_MeasPower", 10e-3, "W", "RIN Measuring power", ParameterType.FLOAT)
        # laser.set_parameter("IncludeRIN", True, "",'Include RIN', ParameterType.BOOL)
        # laser.set_parameter("RandomNumberSeed", 1234, "", "Random number seed", ParameterType.INTEGER)
        templates["LaserCW"] = laser

        # Local Oscillator
        lo = ParameterSet("LO")
        lo.set_parameter("EmissionFrequency", 193.1e12, "Hz", "Emission frequency", ParameterType.FREQUENCY)
        lo.set_parameter("LineWidth", 5e6, "Hz", "Laser linewidth", ParameterType.FREQUENCY)
        lo.set_parameter("Power", 20e-3, "W", "LO power", ParameterType.POWER)
        lo.set_parameter("RIN", -150, "dB/Hz", "RIN", ParameterType.FLOAT)
        # lo.set_parameter("FreqOffset", 0.0, "Hz", "Frequency offset relative to Tx carrier", ParameterType.FREQUENCY)
        # lo.set_parameter("Phase", 0, "deg", "Initial phase", ParameterType.FLOAT)
        templates["LO"] = lo

        # Fiber (SSFM parameters)
        fiber = ParameterSet("Fiber")
        fiber.set_parameter("Length", 20, "km", "Fiber length", ParameterType.LENGTH, min_value=0)
        fiber.set_parameter("Loss_dB_km", 0.17, "dB/km", "Attenuation", ParameterType.FLOAT)
        fiber.set_parameter("Gamma", 1.3e-3, "W^-1 m^-1", "Nonlinear coefficient", ParameterType.FLOAT)
        fiber.set_parameter("Dispersion", 17e-6, "s/m^2",
                            "Group velocity dispersion (D in ps/nm/km converted to s/m^2)", ParameterType.FLOAT)
        # fiber.set_parameter("dz", 1000, "m", "Step size for SSFM", ParameterType.LENGTH)
        # fiber.set_parameter("maxiter", 40, "", "Maximum iterations per step", ParameterType.INTEGER)
        templates["Fiber"] = fiber

        # Polarization emulation (random rotation for LO)
        pol = ParameterSet("PolarizationEmulation")
        pol.set_parameter("alpha", 0.0, "rad", "Rotation angle (alpha)", ParameterType.FLOAT)
        pol.set_parameter("theta1", 0.0, "rad", "Phase delay 1", ParameterType.FLOAT)
        pol.set_parameter("theta2", 0.0, "rad", "Phase delay 2", ParameterType.FLOAT)
        templates["PolarizationEmulation"] = pol

        # Transmitter IQ imbalance (random matrix)
        imb = ParameterSet("TxImbalance")
        # No fixed parameters – seeds are handled in global
        templates["TxImbalance"] = imb

        # Coherent Receiver (90° hybrid + photodiodes)
        icr = ParameterSet("ICR")
        icr.set_parameter("Responsivity", 0.6, "A/W", "PD responsivity", ParameterType.FLOAT, min_value=0)
        icr.set_parameter("PD_BandWidth", 25e9, "Hz", "Photodiode bandwidth", ParameterType.FREQUENCY)
        templates["ICR"] = icr

        # Transimpedance Amplifier (TIA)
        tia = ParameterSet("TIA")
        tia.set_parameter("Gain", 2000, "", "Voltage gain (linear)", ParameterType.FLOAT, min_value=0)
        tia.set_parameter("BandWidth", 50e9, "Hz", "TIA bandwidth", ParameterType.FREQUENCY)
        templates["TIA"] = tia

        # ADC (Keysight UXR0804A)
        adc = ParameterSet("ADC")
        adc.set_parameter("SamplingRate", 256e9, "Hz", "ADC sampling rate", ParameterType.FREQUENCY)
        adc.set_parameter("Resolution", 10, "", "Effective number of bits", ParameterType.INTEGER)
        adc.set_parameter("ADC_BW_Analog", 59e9, "Hz", "ADC analog bandwidth", ParameterType.FREQUENCY)
        # adc.set_parameter("SamplePerSymbol", 1, "", "Downsampling factor after ADC", ParameterType.INTEGER)
        # adc.set_parameter("SamplePhase", 1, "", "Sampling phase (1-indexed)", ParameterType.INTEGER)
        templates["ADC"] = adc

        # Receiver DSP
        onu_rxdsp = ParameterSet("RxDSP")
        onu_rxdsp.set_parameter("EqualizerTaps", 41, "", "CMA equalizer tap count", ParameterType.INTEGER, min_value=1)
        onu_rxdsp.set_parameter("Convergence", 10000, "", "Number of initial convergence symbols", ParameterType.INTEGER)
        onu_rxdsp.set_parameter("StepSize", 1e-3, "", "CMA step size", ParameterType.FLOAT)
        onu_rxdsp.set_parameter("Rolloff", 0.1, "", "Matched filter roll-off", ParameterType.FLOAT)
        onu_rxdsp.set_parameter("PilotBw", 2e9, "Hz", "Pilot extraction filter bandwidth", ParameterType.FREQUENCY)
        onu_rxdsp.set_parameter("PhaseNoiseBw", 10e6, "Hz", "Phase noise compensation filter bandwidth",
                                ParameterType.FREQUENCY)
        templates["RxDSP"] = onu_rxdsp

        olt_rxdsp = ParameterSet("RxDSP")
        olt_rxdsp.set_parameter("EqualizerTaps", 41, "", "CMA equalizer tap count", ParameterType.INTEGER, min_value=1)
        olt_rxdsp.set_parameter("Convergence", 10000, "", "Number of initial convergence symbols", ParameterType.INTEGER)
        olt_rxdsp.set_parameter("StepSize", 1e-3, "", "CMA step size", ParameterType.FLOAT)
        olt_rxdsp.set_parameter("Rolloff", 0.1, "", "Matched filter roll-off", ParameterType.FLOAT)
        olt_rxdsp.set_parameter("PilotBw", 2e9, "Hz", "Pilot extraction filter bandwidth", ParameterType.FREQUENCY)
        olt_rxdsp.set_parameter("PhaseNoiseBw", 10e6, "Hz", "Phase noise compensation filter bandwidth",
                                ParameterType.FREQUENCY)
        templates["RxDSP"] = olt_rxdsp

        # Reuse templates for different roles
        templates["OLTTxDSP"] = olt_tx_dsp
        templates["ONUTxDSP"] = onu_tx_dsp  # Override num_bands=1, grdbw=1e9, SPPR=50 when used
        templates["OLTRxDSP"] = olt_rxdsp
        templates["ONURxDSP"] = onu_rxdsp

        # Polarization rotator (Jones matrix)
        pol_rot = ParameterSet("Pol_Rot")
        pol_rot.set_parameter("Angle", 45.0, "deg", "Rotation angle (azimuth)", ParameterType.FLOAT, min_value=0,
                              max_value=180)
        pol_rot.set_parameter("Ellipticity", 0.0, "rad", "Ellipticity", ParameterType.FLOAT)
        templates["Pol_Rot"] = pol_rot

        # Optical splitter (1×N)
        splitter = ParameterSet("Splitter")
        splitter.set_parameter("N", 4, "", "Number of output ports", ParameterType.INTEGER, min_value=1)
        splitter.set_parameter("ExcessLoss", 0.0, "dB", "Excess loss", ParameterType.POWER, min_value=0)
        templates["Splitter"] = splitter

        # Variable Optical Attenuator (VOA)
        voa = ParameterSet("VOA")
        voa.set_parameter("Scan_ROP_MinVal", 0.0, "dBm", "Scan ROP Min Value", ParameterType.POWER)
        voa.set_parameter("Scan_ROP_MaxVal", 0.0, "dBm", "Scan ROP Max Value", ParameterType.POWER)
        # voa.set_parameter("Attenuation", 0.0, "dB", "Attenuation value", ParameterType.POWER, min_value=0)
        # voa.set_parameter("Active", "On", "", "VOA status", ParameterType.STRING, options=["On", "Off"])
        templates["VOA"] = voa

        # General analyzer (spectrum/eye/constellation)
        analyzer = ParameterSet("Analyzer")
        analyzer.set_parameter("MeasurementType", "Spectrum", "str", "Measurement type", ParameterType.STRING,
                               options=["Spectrum", "EyeDiagram", "Constellation", "BER"])
        analyzer.set_parameter("SweepPoints", 1001, "", "Number of sweep points", ParameterType.INTEGER, min_value=10)
        analyzer.set_parameter("ResultImagePath", "", "", "Auto-generated image path", ParameterType.STRING)
        templates["O-Analyzer"] = analyzer
        templates["E-Analyzer"] = analyzer

        # Power Meter
        power_meter = ParameterSet("PowerMeter")
        power_meter.set_parameter("ReferencePower", 1e-3, "W", "参考功率（0 dBm = 1 mW）", ParameterType.POWER)
        power_meter.set_parameter("DisplayUnit", "dBm", "", "显示单位 (dBm/W/mW)", ParameterType.STRING,
                                  options=["dBm", "W", "mW"])
        templates["PowerMeter"] = power_meter

        return templates

    def load_defaults(self):
        """加载默认的全局参数（基于 MATLAB 下行链路配置）"""
        self._global_params.parameters.clear()
        defaults = {
        }
        for key, (val, unit) in defaults.items():
            self._global_params.set_parameter(key, val, unit)

    def to_dict(self) -> Dict:
        """将全局参数转换为字典（兼容原 GlobalParameters）"""
        result = {}
        for name, param in self._global_params.parameters.items():
            result[name] = [param.value, param.unit]
        return result

    def from_dict(self, data: Dict):
        """从字典加载全局参数（兼容原 GlobalParameters）"""
        for key, value in data.items():
            if isinstance(value, (list, tuple)) and len(value) >= 2:
                self.set_global_value(key, value[0], value[1])
            else:
                self.set_global_value(key, value, "")

    def update_from_dict(self, data: Dict):
        """从字典更新全局参数（兼容原 GlobalParameters）"""
        self.from_dict(data)  # 行为与 from_dict 一致，均为更新/添加

    def get_value(self, key: str):
        """获取全局参数值（兼容原 GlobalParameters）"""
        param = self._global_params.get_parameter(key)
        return param.value if param else None

    def set_value(self, key: str, value: Any, unit: str = ""):
        """设置全局参数值（兼容原 GlobalParameters）"""
        self._global_params.set_parameter(key, value, unit)

    # 更明确的全局参数接口
    def get_global_value(self, key: str, default=None):
        param = self._global_params.get_parameter(key)
        return param.value if param else default

    def set_global_value(self, key: str, value: Any, unit: str = ""):
        self._global_params.set_parameter(key, value, unit)

    def get_global_parameter(self, key: str) -> Optional[Parameter]:
        return self._global_params.get_parameter(key)

    def get_all_global_parameters(self) -> Dict[str, Parameter]:
        return self._global_params.parameters.copy()

    def update_global_from_dict(self, data: Dict):
        """从字典更新全局参数，支持 [value, unit] 格式或直接 value"""
        for key, value in data.items():
            if isinstance(value, (list, tuple)) and len(value) >= 2:
                self.set_global_value(key, value[0], value[1])
            else:
                self.set_global_value(key, value, "")

    # ==================== 组件模板管理 ====================
    def get_template(self, component_type: str) -> ParameterSet:
        """获取组件参数模板"""
        return self.component_templates.get(component_type, ParameterSet(component_type))

    def add_template(self, component_type: str, template: ParameterSet):
        """添加或覆盖组件模板"""
        self.component_templates[component_type] = template

    def get_merged_parameters(self, component_type: str, include_global: bool = True) -> Dict:
        """
        获取合并后的参数字典（组件参数 + 可选的全局参数）

        Args:
            component_type: 组件类型
            include_global: 是否包含全局参数

        Returns:
            参数字典，键为参数名，值为参数值（不含单位）
        """
        result = {}
        if include_global:
            for name, param in self._global_params.parameters.items():
                result[name] = param.value

        template = self.get_template(component_type)
        for name, param in template.parameters.items():
            result[name] = param.value

        return result

    def get_merged_parameters_with_units(self, component_type: str, include_global: bool = True) -> Dict:
        """
        获取合并后的参数及单位
        Returns:
            {param_name: (value, unit)}
        """
        result = {}
        if include_global:
            for name, param in self._global_params.parameters.items():
                result[name] = (param.value, param.unit)

        template = self.get_template(component_type)
        for name, param in template.parameters.items():
            result[name] = (param.value, param.unit)

        return result

    def create_parameter_dialog_data(self, component_type: str, current_params: Dict = None) -> List[Dict]:
        """
        创建用于参数对话框的数据

        Args:
            component_type: 组件类型
            current_params: 当前参数值字典（可选），格式为 {name: value} 或 {name: (value, unit)}

        Returns:
            对话框数据列表，每个元素包含 name, value, unit, description, type, min_value, max_value, options
        """
        template = self.get_template(component_type)
        dialog_data = []

        for param_name, param in template.parameters.items():
            # 获取当前值
            current_value = param.value
            if current_params and param_name in current_params:
                val_data = current_params[param_name]
                if isinstance(val_data, (list, tuple)):
                    current_value = val_data[0] if len(val_data) > 0 else param.value
                else:
                    current_value = val_data

            param_data = {
                "name": param.name,
                "value": current_value,
                "unit": param.unit,
                "description": param.description,
                "type": param.type,
                "min_value": param.min_value,
                "max_value": param.max_value,
                "options": param.options
            }
            dialog_data.append(param_data)

        return dialog_data

    def validate_parameters(self, component_type: str, parameters: Dict) -> List[str]:
        """
        验证给定参数字典是否符合组件模板的定义

        Args:
            component_type: 组件类型
            parameters: 待验证的参数字典，格式 {name: value}

        Returns:
            错误消息列表
        """
        template = self.get_template(component_type)
        errors = []
        for param_name, param in template.parameters.items():
            if param_name in parameters:
                try:
                    _ = Parameter(param_name, parameters[param_name],
                                  param.unit, param.description, param.type,
                                  param.min_value, param.max_value, param.options)
                except ValueError as e:
                    errors.append(str(e))
        return errors

    def save_templates(self, filepath: str):
        """将所有模板（包括全局参数）保存到 JSON 文件"""
        data = {name: template.to_dict() for name, template in self.component_templates.items()}
        with open(filepath, 'w') as f:
            json.dump(data, f, indent=2, default=str)

    def load_templates(self, filepath: str):
        """从 JSON 文件加载模板（会覆盖现有模板）"""
        with open(filepath, 'r') as f:
            data = json.load(f)
        for name, template_data in data.items():
            self.component_templates[name] = ParameterSet.from_dict(template_data)
        # 确保全局参数集被正确指向
        self._global_params = self.component_templates.get("Global", ParameterSet("Global"))
        self.component_templates["Global"] = self._global_params

    def __repr__(self):
        return f"ParameterManager(global_params={len(self._global_params.parameters)}, component_templates={len(self.component_templates)})"


# 向后兼容：保留原 GlobalParameters 类作为适配器（可选）
class GlobalParameters:
    """向后兼容的全局参数类，实际委托给 ParameterManager 的全局部分"""

    def __init__(self):
        self._manager = ParameterManager()

    def load_defaults(self):
        self._manager.load_defaults()

    def to_dict(self):
        return self._manager.to_dict()

    def from_dict(self, data):
        self._manager.from_dict(data)

    def update_from_dict(self, data):
        self._manager.update_from_dict(data)

    def get_value(self, key):
        return self._manager.get_value(key)

    def set_value(self, key, value, unit=""):
        self._manager.set_value(key, value, unit)